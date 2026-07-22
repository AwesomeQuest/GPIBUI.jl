
mutable struct GPIBNames
    keithley_name::String
    spectra_name::String
end
const GPIBCONFIG = Ref(GPIBNames("", ""))

function my_read_open(ctx, handler, name)
    @debug "read open called"
    return pointer_from_objref(GPIBCONFIG)
end
function my_read_line(ctx, handler, entry, line)
    @debug "read line called"
    s = unsafe_pointer_to_objref(entry)::Ref{GPIBNames}
    l = unsafe_string(line)
    if startswith(l, "keithley=")
        s[].keithley_name = l[11:end-1]
    elseif startswith(l, "spectra=")
        s[].spectra_name = l[10:end-1]
    end
    return
end
function my_write_all(ctx, handler, buf)
    @debug "write all called with $(GPIBCONFIG[])"
    ig.Appendf(buf, "[GPIBUI][Settings]\n")
    ig.Appendf(buf, "keithley=\"$(GPIBCONFIG[].keithley_name)\"\n")
    ig.Appendf(buf, "spectra=\"$(GPIBCONFIG[].spectra_name)\"\n")
    return
end
