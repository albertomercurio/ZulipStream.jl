# ZulipStream.jl

[![Build Status](https://github.com/albertomercurio/ZulipStream.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/albertomercurio/ZulipStream.jl/actions/workflows/CI.yml?query=branch%3Amain)

A Julia package to stream real-time computation progress and results to [Zulip](https://zulip.com/). All output is automatically sent to **both stdout and Zulip**, keeping your terminal and team chat in sync.

## Features

- 📊 **Progress Bar Streaming**: Automatically send progress bar updates to both your terminal and Zulip
- 📝 **Markdown Support**: Send formatted tables, headers, and text to both outputs simultaneously
- ⏱️ **Rate Limiting**: Control update frequency to avoid API spam
- 🔄 **Auto-detection**: Intelligently handles both progress bars and multi-line output
- 📡 **Real-time Updates**: Updates existing messages instead of creating new ones
- 🔄 **Dual Output**: All output goes to both stdout and Zulip seamlessly

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/albertomercurio/ZulipStream.jl")
```

## Setup

First, create a Zulip bot and get your credentials:
1. Go to your Zulip organization settings
2. Create a new bot account (important: choose "Generic bot" type)
3. Copy the bot email and API key

Then configure ZulipStream:

```julia
using ZulipStream

# Configure your Zulip settings
ZulipStream.settings.ZULIP_URL  = "https://your-org.zulipchat.com/api/v1"
ZulipStream.settings.BOT_EMAIL  = "your-bot@your-org.zulipchat.com"
ZulipStream.settings.API_KEY    = "your_api_key_here"
```

## Usage

### Example 1: Progress Bar Updates

Stream a progress bar to both your terminal and Zulip with automatic updates:

```julia
using ZulipStream
using ProgressMeter

# Create a ZulipIO stream
z_io = ZulipIO(
    channel = "general",      # Zulip channel/stream name
    topic   = "Progress Updates",  # Topic name
    freq    = 2.0             # Update frequency in seconds
)

# Use it with ProgressMeter
n = 100
p = Progress(n; output=z_io, desc="Computing: ")

for i in 1:n
    # Your computation here
    sleep(0.1)
    next!(p)
end
```

The progress bar will be automatically posted and updated on both your terminal and Zulip every 2 seconds.

### Example 2: Markdown Tables and Formatted Output

Send formatted tables and markdown content:

```julia
using ZulipStream

z_io = ZulipIO(
    channel = "general",
    topic   = "Simulation Results",
    freq    = 5.0
)

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
```

The table will be rendered properly in both your terminal and Zulip with full markdown formatting.

## API Reference

### `ZulipIO`

```julia
ZulipIO(; channel="general", topic="Simulations", freq=30.0)
```

Creates an IO stream that sends output to Zulip.

**Parameters:**
- `channel::String`: The Zulip channel/stream name (default: "general")
- `topic::String`: The topic name (default: "Simulations")
- `freq::Float64`: Minimum seconds between updates (default: 30.0)

**Usage:**
- Use with `println()`, `print()`, or any IO function—output goes to both stdout and Zulip
- Use as `output` parameter in [ProgressMeter.Progress](https://github.com/timholy/ProgressMeter.jl)
- Call `flush()` to trigger an update (respects timing constraint)

### Configuration

Configure your [Zulip](https://zulip.com/) bot credentials:

```julia
ZulipStream.settings.ZULIP_URL   # Base API URL (e.g., https://your-org.zulipchat.com/api/v1)
ZulipStream.settings.BOT_EMAIL   # Bot email address
ZulipStream.settings.API_KEY     # Bot API key
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
