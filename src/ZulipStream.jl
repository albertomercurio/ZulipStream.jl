module ZulipStream

using HTTP, JSON, Base64, URIs
using Dates

export ZulipIO

"""
    ZulipStreamSettings

Struct per memorizzare le impostazioni di connessione a Zulip.

# Arguments
- `ZULIP_URL::String`: URL base dell'API di Zulip. Esempio: `https://organization.zulipchat.com/api/v1`.
- `BOT_EMAIL::String`: Email del bot Zulip. Esempio: `bot-name@organization.zulipchat.com`.
- `API_KEY::String`: Chiave API del bot Zulip. Esempio: `fce22d2wxefc23edc2wsd`.
"""
mutable struct ZulipStreamSettings
    ZULIP_URL::String
    BOT_EMAIL::String
    API_KEY::String
end

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

Send a status update to Zulip. If `message_id` is provided, it updates the existing message; otherwise, it creates a new message.
"""
function update_zulip_status(content, message_id=nothing; channel="general", topic="Simulations")
    if isnothing(message_id)
        # POST: Creazione nuovo messaggio
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
        # PATCH: Aggiornamento messaggio esistente
        url = "$(settings.ZULIP_URL)/messages/$message_id"
        
        # Codifichiamo il contenuto per il formato x-www-form-urlencoded
        body_str = "content=" * URIs.escapeuri(content)
        headers = vcat(auth_header(settings), ["Content-Type" => "application/x-www-form-urlencoded"])
        
        HTTP.request("PATCH", url, headers, body_str)
        return message_id
    end
end

mutable struct ZulipIO <: IO
    buffer::IOBuffer
    last_update::Float64
    update_freq::Float64
    msg_id::Union{Int, Nothing}
    channel::String
    topic::String
    last_content::String
    
    ZulipIO(; channel="general", topic="Simulations", freq=30.0) = 
        new(IOBuffer(), 0.0, freq, nothing, channel, topic, "")
end

function Base.write(s::ZulipIO, b::UInt8)
    # 1. Write to stdout for local terminal
    write(stdout, b)
    
    # 2. Accumulate in buffer
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
    
    # Check timing and if content has changed
    current_time = time()
    if (current_time - s.last_update) > s.update_freq && final_content != s.last_content
        timestamp = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
        zulip_msg = """
        📊 **Simulations Status**
        
        $final_content
        
        *Last updated: $timestamp*
        """
        
        try
            s.msg_id = update_zulip_status(
                zulip_msg, 
                s.msg_id; 
                channel=s.channel, 
                topic=s.topic
            )
            s.last_update = current_time
            s.last_content = final_content
        catch e
            @warn "Errore Zulip: $e"
        end
    end
end

end
