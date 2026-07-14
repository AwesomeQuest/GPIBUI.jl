using Dates, TimesDates
using NativeFileDialog, DelimitedFiles

function savetofile(times, currs, volts, timestamp_mode, filepath)
	open(filepath, "w") do io
		isempty(times) && return
		time = copy(times)
		if timestamp_mode === :datetime
			timedatenow, nanonow = TimeDate(Dates.now()), BetterSleep.now()
			synthetic_first_time = timedatenow - Nanosecond((nanonow - time[1]).ns)
			time = [synthetic_first_time + Nanosecond((tt - time[1]).ns) for tt in time]
			timeunit = "[DateTime]"
		elseif timestamp_mode === :seconds
			time = (time .- [time[1]]) .|> x->x.ns/1e9
			timeunit = "[Seconds]"
		else
			time = time .|> x->x.ns
			timeunit = "[Nanoseconds]"
		end
		writedlm(io, ["TimeStamp "*timeunit "Voltage [V]" "Current [A]"], ',')
		writedlm(io, [time volts currs], ',')
	end
end
