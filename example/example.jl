using ZulipStream
using ProgressMeter
using DotEnv

DotEnv.load!()

ZulipStream.settings.ZULIP_URL  = ENV["ZULIP_URL"]
ZulipStream.settings.BOT_EMAIL  = ENV["ZULIP_BOT_EMAIL"]
ZulipStream.settings.API_KEY    = ENV["ZULIP_API_KEY"]

n = 10

z_io = ZulipIO(
    channel = "general", 
    topic   = "Progress Updates", 
    freq    = 2.0
)

p = Progress(n; output=z_io, desc="Calcolo in corso: ")

for i in 1:n
    sleep(2)
    next!(p)
end
