module ZulipStream

using HTTP, JSON, Base64, URIs
using Dates

export ZulipIO

"""
    ZulipStreamSettings

Struct to store connection settings for Zulip.

This struct holds the credentials and connection information necessary to authenticate and communicate
with a Zulip server via its API.

# Fields
- `ZULIP_URL::String`: Base URL of the Zulip API. Example: `https://organization.zulipchat.com/api/v1`.
- `BOT_EMAIL::String`: Email address of the Zulip bot. Example: `bot-name@organization.zulipchat.com`.
- `API_KEY::String`: API key of the Zulip bot. Example: `fce22d2wxefc23edc2wsd`.

# Examples
```julia
settings = ZulipStreamSettings(
    "https://myorg.zulipchat.com/api/v1",
    "bot@myorg.zulipchat.com",
    "your_api_key_here"
)
```
"""
mutable struct ZulipStreamSettings
    ZULIP_URL::String
    BOT_EMAIL::String
    API_KEY::String
end

# Global settings instance for Zulip connection
const settings = ZulipStreamSettings(
    "https://organization.zulipchat.com/api/v1",
    "bot-name@organization.zulipchat.com",
    "your_api_key_here",
)

function Base.show(io::IO, ::MIME"text/plain", settings::ZulipStreamSettings)
    println(io, "ZulipStreamSettings:")
    println(io, "  ZULIP_URL: ", settings.ZULIP_URL)
    println(io, "  BOT_EMAIL: ", settings.BOT_EMAIL)
    println(io, "  API_KEY: ", settings.API_KEY[1:4] * "*"^(length(settings.API_KEY)-8) * settings.API_KEY[end-3:end])
end

auth_header(settings::ZulipStreamSettings) = ["Authorization" => "Basic " * base64encode("$(settings.BOT_EMAIL):$(settings.API_KEY)")]

"""
    update_zulip_status(content, message_id=nothing; channel="general", topic="Simulations")

Send or update a status message in a Zulip stream.

This function either creates a new message or updates an existing one, depending on whether a message ID is provided.
New messages are posted to the specified channel and topic. Updates modify the content of an existing message.

# Arguments
- `content::String`: The message content to send or the updated content for an existing message.
- `message_id::Union{Int, Nothing}`: Optional message ID. If provided, updates the message with this ID; otherwise creates a new message.

# Keywords
- `channel::String`: The target stream/channel name (default: `"general"`).
- `topic::String`: The topic within the channel (default: `"Simulations"`).

# Returns
- `Int`: The message ID of the created or updated message.

# Errors
Throws an exception if the HTTP request to Zulip fails (network error, authentication error, etc.).
"""
function update_zulip_status(content, message_id=nothing; channel="general", topic="Simulations")
    if isnothing(message_id)
        # POST: Create a new message
        url = "$(settings.ZULIP_URL)/messages"
        body = HTTP.Form(Dict(
            "type" => "stream",
            "to" => channel,
            "topic" => topic,
            "content" => content
        ))
        res = HTTP.post(url, auth_header(settings), body)
        return JSON.parse(String(res.body))["id"]
    else
        # PATCH: Update an existing message
        url = "$(settings.ZULIP_URL)/messages/$message_id"
        
        # Encode the content in x-www-form-urlencoded format
        body_str = "content=" * URIs.escapeuri(content)
        headers = vcat(auth_header(settings), ["Content-Type" => "application/x-www-form-urlencoded"])
        
        HTTP.request("PATCH", url, headers, body_str)
        return message_id
    end
end

"""
    ZulipIO <: IO

A custom IO stream that outputs to both stdout and a Zulip channel.

This type implements the IO interface to capture written content and periodically send updates to a Zulip stream.
It intelligently handles both progress bars (with carriage returns) and normal output, removing ANSI color codes
and sending updates at configurable intervals to avoid rate limiting.

# Fields
- `buffer::IOBuffer`: Accumulates written content before sending.
- `last_update::Float64`: Timestamp of the last message sent to Zulip.
- `update_freq::Float64`: Minimum time (in seconds) between consecutive message updates.
- `msg_id::Union{Int, Nothing}`: ID of the current Zulip message (used for updates).
- `channel::String`: The Zulip stream/channel to send messages to.
- `topic::String`: The topic within the channel to send messages to.
- `last_content::String`: The last content that was sent to avoid duplicate messages.
- `send_timer::Timer`: Timer object for scheduling deferred message sends.

# Constructor
```julia
ZulipIO(; channel="general", topic="Simulations", freq=60.0)
```

# Keywords
- `channel::String`: The target Zulip stream name (default: `"general"`).
- `topic::String`: The topic within the channel (default: `"Simulations"`).
- `freq::Float64`: Minimum seconds between message updates (default: `60.0`).

# Examples
```julia
zio = ZulipIO(channel="my-stream", topic="Status", freq=30.0)
println(zio, "Computation started...")
flush(zio)  # Sends update to Zulip
```
"""
mutable struct ZulipIO <: IO
    buffer::IOBuffer
    last_update::Float64
    update_freq::Float64
    msg_id::Union{Int, Nothing}
    channel::String
    topic::String
    last_content::String
    send_timer::Timer
    
    ZulipIO(; channel="general", topic="Simulations", freq=60.0) = 
        new(IOBuffer(), 0.0, freq, nothing, channel, topic, "", Timer(0))
end

function Base.write(s::ZulipIO, b::UInt8)
    # Write to stdout for local terminal display
    write(stdout, b)
    
    # Accumulate in buffer for Zulip transmission
    write(s.buffer, b)
    
    return 1
end

function Base.flush(s::ZulipIO)
    # Flush stdout first
    flush(stdout)
    
    # Get current buffer content
    current_content = String(take!(s.buffer))
    
    if isempty(current_content)
        return
    end
    
    # Smart detection: progress bar vs normal output
    has_carriage_return = contains(current_content, '\r')
    
    if has_carriage_return
        # Progress bar mode: only send the last line (overwritten with \r)
        lines = split(current_content, r"[\r\n]")
        clean_str = filter(!isempty, strip.(lines))
        
        if isempty(clean_str)
            return
        end
        
        # Remove ANSI color codes
        final_content = replace(last(clean_str), r"\e\[[0-9;]*[a-zA-Z]" => "")
    else
        # Normal output mode: send all accumulated lines
        lines = split(current_content, '\n')
        clean_str = filter(!isempty, strip.(lines))
        
        if isempty(clean_str)
            return
        end
        
        # Join all lines and remove ANSI color codes
        final_content = replace(join(clean_str, '\n'), r"\e\[[0-9;]*[a-zA-Z]" => "")
    end
    
    # Cancel any pending timer
    close(s.send_timer)
    
    # Calculate delay: time since last update, respecting the minimum update frequency
    current_time = time()
    time_since_last = current_time - s.last_update
    delay = max(0.0, s.update_freq - time_since_last)
    
    # Schedule send after delay to respect rate limiting
    s.send_timer = Timer(delay) do timer
        # Only send if content has changed since last transmission
        if final_content != s.last_content
            timestamp = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
            final_content_block = has_carriage_return ? "```\n$final_content\n```" : final_content
            zulip_msg = """
            📊 **Simulations Status**
            
            $final_content_block
            
            *Last updated: $timestamp*
            """
            
            try
                s.msg_id = update_zulip_status(
                    zulip_msg, 
                    s.msg_id; 
                    channel=s.channel, 
                    topic=s.topic
                )
                s.last_update = time()
                s.last_content = final_content
            catch e
                @warn "Zulip error: $e"
            end
        end
    end
end

end
