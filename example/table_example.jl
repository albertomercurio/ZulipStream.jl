using ZulipStream
using Markdown
using DotEnv

DotEnv.load!()

ZulipStream.settings.ZULIP_URL  = ENV["ZULIP_URL"]
ZulipStream.settings.BOT_EMAIL  = ENV["ZULIP_BOT_EMAIL"]
ZulipStream.settings.API_KEY    = ENV["ZULIP_API_KEY"]

# Create ZulipIO with longer update frequency since we're updating a table
z_io = ZulipIO(
    channel = "Floquet Dissipative Phase Transitions", 
    topic   = "Simulations Status", 
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
    
    # Build a markdown table using Markdown.jl
    table = Markdown.parse("""
    ### Iteration $(iter)/$(n_iterations)
    
    | Parameter       | Value              | Unit   |
    |-----------------|-------------------:|--------|
    | Temperature     | $(round(temperature, digits=2)) | K      |
    | Energy          | $(round(energy, sigdigits=4)) | eV     |
    | Convergence     | $(round(convergence, sigdigits=3)) | -      |
    | Accuracy        | $(round(accuracy, digits=1))% | -      |
    
    **Status**: $(iter == n_iterations ? "✅ Complete" : "🔄 Running...")
    """)
    
    # Print the Markdown.MD object - will be detected and rendered as markdown
    println(z_io, table)
    
    # Flush to send to Zulip (respects timing constraint)
    flush(z_io)
end

println("\nSimulation complete!")
