function initialize_spectra()
    @debug_once "Asking gratings"
    listG = split(ask_spectra("GRATINGS"), '\r', keepempty=false) .|> filter(isprint) .|> strip
    @debug_once "Asking turrets"
    listT = split(ask_spectra("TURRETS"), '\r', keepempty=false) .|> filter(isprint) .|> strip
    filter!(!=(""), listT)

    return listG, listT
end

function spectrastatusmonitor()
    while !SPECTRA.kill[]
        @debug_once "Getting status"
        nm = ask_spectra("NM")
        nmmin = ask_spectra("NM/MIN")
        nmjog = ask_spectra("NM/JOG")
        selectedG = ask_spectra("GRATING")
        selectedT = ask_spectra("TURRET")

        nm = parse(Float64, nm)
        nmmin = parse(Float64, nmmin)
        nmjog = parse(Float64,  match(r"[\d\.\-]+", nmjog).match)
        grating = parse(Int, selectedG)
        turret = parse(Int, selectedT)
        @atomic SPECTRA.status = SpectraStatus(true, nm, nmmin, nmjog, turret, grating)

        interuptsleep(SPECTRA.config.status_update_interval, SPECTRA.kill, SPECTRA.config.sleep_interrupt_interval)
    end
end

# NOTE: NEVER try to read from the spectrapro 150 unless it is indicating 
# that you can read from it!
function spectramanager()
    CMDBIT = 0b0000_0001
    ERRBIT = 0b0000_0010
    RESBIT = 0b1000_0000
    
    while !SPECTRA.kill[]
        S::UInt16 = statusbyte(SPECTRA.gpib)
        @debug_changed "Status byte is $S"
        if S & ERRBIT != 0
            @debug "Found error"
            if S & RESBIT != 0
                output = ""
                @lock GPIB_LOCK output = read(SPECTRA.gpib)
                @error output
            else
                @warn "The Spectra is indicating an error but has nothing to read"
            end
            continue
        elseif S & RESBIT != 0
            @debug "Reading from Spectra"
            try
                @lock GPIB_LOCK put!(SPECTRA.output, read(SPECTRA.gpib))
            catch e
                @error e
                @warn "Clearing GPIB"
                clear(SPECTRA.gpib)
            end
        elseif S & CMDBIT != 0 && isready(SPECTRA.input)
            @debug "Sending command $(fetch(SPECTRA.input))"
            @lock GPIB_LOCK write(SPECTRA.gpib, take!(SPECTRA.input)*"\r")
        end
        interuptsleep(SPECTRA.config.sample_rate, SPECTRA.kill, SPECTRA.config.sleep_interrupt_interval)
    end
end

function ask_spectra(name)
    @lock SPECTRA.io_lock begin
        put!(SPECTRA.input, "?"*name)
        return take!(SPECTRA.output)
    end
end

function tell_spectra(cmd)
    @lock SPECTRA.io_lock begin
        # Send the message
        put!(SPECTRA.input, cmd)
        # Wait until the message was consumed
        while isready(SPECTRA.input) yield() end
        # Make sure the message finished sending
        @lock GPIB_LOCK yield()
        # Wait for the Spectra to finish executing the message
        while statusbyte(SPECTRA.gpib) == 0x00
            interuptsleep(millis(100), SPECTRA.kill, SPECTRA.config.sleep_interrupt_interval)
        end
        return nothing
    end
end