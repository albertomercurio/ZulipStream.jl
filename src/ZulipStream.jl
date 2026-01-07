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

A custom IO stream that outputs to a configurable IO stream and sends updates to a Zulip channel.

This type implements the IO interface to capture written content and periodically send updates to a Zulip stream.
It intelligently handles both progress bars (with carriage returns) and normal output, removing ANSI color codes
and sending updates at configurable intervals to avoid rate limiting. Output can be directed to any IO stream
(e.g., stdout, a file, or devnull) via the `io` keyword argument.

# Fields
- `buffer::IOBuffer`: Accumulates written content before sending.
- `last_update::Float64`: Timestamp of the last message sent to Zulip.
- `update_freq::Float64`: Minimum time (in seconds) between consecutive message updates.
- `msg_id::Union{Int, Nothing}`: ID of the current Zulip message (used for updates).
- `channel::String`: The Zulip stream/channel to send messages to.
- `topic::String`: The topic within the channel to send messages to.
- `last_content::String`: The last content that was sent to avoid duplicate messages.
- `send_timer::Timer`: Timer object for scheduling deferred message sends.
- `io::IO`: The local IO stream for standard output (e.g., stdout).
- `title::String`: Custom title for the Zulip message (default: "📊 **Status Update**").
- `show_hostname::Bool`: Whether to include hostname in the message (default: `false`).
- `show_julia_version::Bool`: Whether to include Julia version in the message (default: `false`).
- `show_timestamp::Bool`: Whether to include timestamp in the message (default: `true`).
- `custom_footer::String`: Custom footer text to append to messages (default: "").

# Constructor
```julia
ZulipIO(; channel="general", topic="Simulations", freq=60.0, io=stdout, 
        title="📊 **Status Update**", show_hostname=true, show_julia_version=true,
        show_timestamp=true, custom_footer="")
```

# Keywords
- `channel::String`: The target Zulip stream name (default: `"general"`).
- `topic::String`: The topic within the channel (default: `"Simulations"`).
- `freq::Float64`: Minimum seconds between message updates (default: `60.0`).
- `io::IO`: The IO stream for local output (default: `stdout`).
- `title::String`: Custom title for messages (default: `"📊 **Status Update"`).
- `show_hostname::Bool`: Include hostname in messages (default: `false`).
- `show_julia_version::Bool`: Include Julia version in messages (default: `false`).
- `show_timestamp::Bool`: Include timestamp in messages (default: `true`).
- `custom_footer::String`: Custom footer text (default: `""`).

# Examples
```julia
# Basic usage
zio = ZulipIO(channel="my-stream", topic="Status", freq=30.0)
println(zio, "Computation started...")
flush(zio)  # Sends update to Zulip

# With custom title and system info
zio = ZulipIO(
    channel="simulations",
    topic="ML Training",
    title="🚀 **Model Training Progress**",
    show_hostname=true,
    show_julia_version=true,
    custom_footer="Contact: admin@example.com"
)
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
    io::IO
    title::String
    show_hostname::Bool
    show_julia_version::Bool
    show_timestamp::Bool
    custom_footer::String
    
    ZulipIO(; channel="general", topic="Simulations", freq=60.0, io::IO=stdout,
            title="📊 **Status Update**", show_hostname=true, show_julia_version=true,
            show_timestamp=true, custom_footer="") = 
        new(IOBuffer(), 0.0, freq, nothing, channel, topic, "", Timer(0), io,
            title, show_hostname, show_julia_version, show_timestamp, custom_footer)
end

function Base.write(s::ZulipIO, b::UInt8)
    # Write to configured IO stream for local display
    write(s.io, b)
    
    # Accumulate in buffer for Zulip transmission
    write(s.buffer, b)
    
    return 1
end

function Base.flush(s::ZulipIO)
    # Flush configured IO stream first
    flush(s.io)
    
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
    
    if isnothing(s.msg_id)
        # First message: send synchronously to ensure msg_id is set before next flush
        _send_zulip_message!(s, final_content, has_carriage_return)
    else
        # Subsequent updates: schedule via Timer to respect rate limiting
        s.send_timer = Timer(delay) do timer
            _send_zulip_message!(s, final_content, has_carriage_return)
        end
    end
end

function _send_zulip_message!(s::ZulipIO, final_content::String, has_carriage_return::Bool)
    # Only send if content has changed since last transmission
    if final_content == s.last_content
        return
    end
    
    # Build the message with configurable components
    msg_parts = String[]
    
    # Add title
    push!(msg_parts, s.title)
    push!(msg_parts, "")  # Empty line
    
    # Add system information if requested
    system_info = String[]
    if s.show_hostname
        push!(system_info, "🖥️  **Hostname:** $(gethostname())")
    end
    if s.show_julia_version
        push!(system_info, "💎 **Julia:** v$(VERSION)")
    end
    
    if !isempty(system_info)
        push!(msg_parts, join(system_info, "  \n"))
        push!(msg_parts, "")  # Empty line
    end
    
    # Add main content
    final_content_block = has_carriage_return ? "```\n$final_content\n```" : final_content
    push!(msg_parts, final_content_block)
    
    # Add timestamp if requested
    if s.show_timestamp
        timestamp = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
        push!(msg_parts, "")  # Empty line
        push!(msg_parts, "*Last updated: $timestamp*")
    end
    
    # Add custom footer if provided
    if !isempty(s.custom_footer)
        push!(msg_parts, "")  # Empty line
        push!(msg_parts, s.custom_footer)
    end
    
    zulip_msg = join(msg_parts, "\n")
    
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
    
    return nothing
end

end
