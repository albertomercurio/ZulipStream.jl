using ZulipStream
using DotEnv

DotEnv.load!()

ZulipStream.settings.ZULIP_URL  = ENV["ZULIP_URL"]
ZulipStream.settings.BOT_EMAIL  = ENV["ZULIP_BOT_EMAIL"]
ZulipStream.settings.API_KEY    = ENV["ZULIP_API_KEY"]

# Create ZulipIO with longer update frequency since we're updating a table
z_io = ZulipIO(
    channel = "general", 
    topic   = "Simulation Results", 
    freq    = 5.0  # Update every 5 seconds
)

# Simulate a computation with time-varying parameters
n_iterations = 10

for iter in 1:n_iterations
    # Simulate some computation
    sleep(3)
    
    # Calculate time-dependent parameters
    temperature = 300 + 50 * sin(2π * iter / n_iterations)
    energy = 1.5e-3 * iter^1.2
    convergence = 1.0 / (iter + 1)
    accuracy = (1 - exp(-iter/3)) * 100
    
    # Build a markdown table
    println(z_io, "### Iteration $iter/$n_iterations")
    println(z_io, "")
    println(z_io, "| Parameter       | Value              | Unit   |")
    println(z_io, "|-----------------|-------------------:|--------|")
    println(z_io, "| Temperature     | $(round(temperature, digits=2)) | K      |")
    println(z_io, "| Energy          | $(round(energy, sigdigits=4)) | eV     |")
    println(z_io, "| Convergence     | $(round(convergence, sigdigits=3)) | -      |")
    println(z_io, "| Accuracy        | $(round(accuracy, digits=1))% | -      |")
    println(z_io, "")
    println(z_io, "**Status**: $(iter == n_iterations ? "✅ Complete" : "🔄 Running...")")
    
    # Flush to send to Zulip (respects timing constraint)
    flush(z_io)
end

println("\nSimulation complete!")
