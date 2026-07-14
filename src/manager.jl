include("spectra.jl")

# global event_list::Vector{String} = []

function getevents()
	global is_connected
	is_connected || nodeviceconnected() || return
	global event_list
	global selected_keithley_type
	noerr = "No error"

	while true
		global gpiblock
		output = ""
		if keithley_types[selected_keithley_type] == "MODEL 2400"
			@lock gpiblock output = query(Keithley, "STAT:QUE:NEXT?")
		elseif keithley_types[selected_keithley_type] == "MODEL 2470"
			@lock gpiblock output = query(Keithley, "SYST:EVEN:NEXT?")
		else
			@assert false "Unreachable!"
		end
		occursin(noerr, output) && break
		@info output
		push!(event_list, output)
	end
end

function initialize_keithley()
	global Keithley
	global is_connected
	is_connected || nodeviceconnected() || return

	
	write(Keithley, "*RST")
	write(Keithley, "SOUR:FUNC VOLT")
	write(Keithley, "SENS:FUNC 'CURR'")
	if keithley_types[selected_keithley_type] == "MODEL 2400"
		write(Keithley, "FORM:ELEM VOLT,CURR")
	elseif keithley_types[selected_keithley_type] == "MODEL 2470"
		write(Keithley, ":FORM:ASC:PREC 16")
	end
	errormonitor(Threads.@spawn getevents())
	return
end

function monitor(volts_set, maxcurrent)
	global is_connected
	is_connected || nodeviceconnected() || return
	global Keithley
	global rt_is_monitoring
	global rt_cancel_monitor
	global rt_sample_period

	errormonitor(Threads.@spawn getevents())
	if keithley_types[selected_keithley_type] == "MODEL 2400"
		write(Keithley, "SENS:CURR:PROT $(maxcurrent)")
	elseif keithley_types[selected_keithley_type] == "MODEL 2470"
		write(Keithley, "SOUR:VOLT:ILIMIT $(maxcurrent)")
	else
		@assert false "Unreachable!"
	end
	write(Keithley, "SOUR:VOLT $(volts_set)")
	write(Keithley, "OUTP ON")

	if keithley_types[selected_keithley_type] == "MODEL 2470"
		write(Keithley, "CURR:AZER ON")
		write(Keithley, "VOLT:AZER ON")
		query(Keithley, "MEAS:CURR?")
		query(Keithley, "MEAS:VOLT?")
		write(Keithley, "CURR:AZER OFF")
		write(Keithley, "VOLT:AZER OFF")
	end

	rt_is_monitoring[] = true
	while !rt_cancel_monitor[]
		interuptsleep(rt_sample_period, rt_cancel_monitor, sleep_interupt_interval)
		meascurr, measvolt = "", ""
		global gpiblock
		@lock gpiblock begin
			meascurr = query(Keithley, "MEAS:CURR?")
			measvolt = query(Keithley, "MEAS:VOLT?")
		end
		try
			if keithley_types[selected_keithley_type] == "MODEL 2400"
				_, curr = split(meascurr, ',')
				volt, _ = split(measvolt, ',')
				curr = parse(Float64, curr)
				volt = parse(Float64, volt)
			elseif keithley_types[selected_keithley_type] == "MODEL 2470"
				curr = parse(Float64, meascurr)
				volt = parse(Float64, measvolt)
			else
				curr = volt = 0.0
				@assert false "Unreachable!"
			end
			global plotlock
			@lock plotlock begin
				global rt_times
				global rt_currs
				global rt_volts
				push!(rt_times, now())
				push!(rt_currs, curr)
				push!(rt_volts, volt)
			end
		catch e
			@error e
		end
	end
	rt_is_monitoring[] = false

	write(Keithley, "OUTP OFF")
	errormonitor(Threads.@spawn getevents())
	return
end

function integrated_2400_sweep(min_volts, max_volts, step_voltage, delay, maxcurrent)
	global is_connected
	is_connected || nodeviceconnected() || return
	global Keithley
	global iv_is_sweeping
	global iv_cancel_sweep

	@assert length(min_volts:step_voltage:max_volts) > 2500 "Step size too small. Maximum number of points is 2500, got $(length(min_volts:step_voltage:max_volts))"
	
	data = ""
	@lock gpiblock begin
		write(Keithley, "*RST")
		write(Keithley, "SENS:FUNC:CONC OFF")
		write(Keithley, "SOUR:FUNC VOLT")
		write(Keithley, "SENS:FUNC 'CURR:DC'")
		write(Keithley, "SENS:CURR:PROT $(maxcurrent)")
		write(Keithley, "SOUR:VOLT:STAR $min_volts")
		write(Keithley, "SOUR:VOLT:STOP $max_volts")
		write(Keithley, "SOUR:VOLT:STEP $step_voltage")
		write(Keithley, "SOUR:VOLT:MODE SWE")
		write(Keithley, "SOUR:SWE:RANG AUTO")
		write(Keithley, "SOUR:SWE:SPAC LIN")
		write(Keithley, "TRIG:COUN $(length(min_volts:step_voltage:max_volts))")
		write(Keithley, "SOUR:DEL $delay")
		write(Keithley, "SOUR:SWE:DIR UP")
	
		data = query(Keithley, "READ?")
	end
	data = split(data, ',') .|> x->parse(Float64, x)
	data = reshape(data, 2, :)
	@lock plotlock begin
		global iv_volts, iv_currs
		iv_volts = @view data[1, :]
		iv_currs = @view data[2, :]
	end

	
end

function sweep(min_volts, max_volts, step_voltage, delay, maxcurrent, dual)
	global is_connected
	is_connected || nodeviceconnected() || return
	global Keithley
	global iv_is_sweeping, iv_cancel_sweep
	global selected_keithley_type

	errormonitor(Threads.@spawn getevents())
	global  gpiblock
	@lock gpiblock begin
		if keithley_types[selected_keithley_type] == "MODEL 2400"
			write(Keithley, "SENS:CURR:PROT $(maxcurrent)")
		elseif keithley_types[selected_keithley_type] == "MODEL 2470"
			write(Keithley, "SOUR:VOLT:ILIMIT $(maxcurrent)")
			D = dual ? "ON" : "OFF"
			write(Keithley, "SOUR:SWE:VOLT:LIN:STEP $min_volts, $max_volts, $step_voltage, $delay, 1, AUTO, ON, $D")
		else
			@assert false "Unreachable!"
		end
	end

	global iv_times, iv_volts, iv_currs
	@lock plotlock begin
		empty!(iv_times)
		empty!(iv_volts)
		empty!(iv_currs)
	end
	
	@lock gpiblock begin
		write(Keithley, "SOUR:VOLT 0")
		write(Keithley, "OUTP ON")
		if keithley_types[selected_keithley_type] == "MODEL 2470"
			write(Keithley, "INIT")
		end
	end
	stepvals = calculate_sweep(min_volts, max_volts, step_voltage, dual)
	if keithley_types[selected_keithley_type] == "MODEL 2400"
		voltssize = length(stepvals)
	elseif keithley_types[selected_keithley_type] == "MODEL 2470"
		voltssize = ""
		@lock gpiblock voltssize = query(Keithley, "SOUR:CONF:LIST:SIZE? \"VoltLinearSweepList\"")
		voltssize = parse(Int, voltssize)
	else
		@assert false "Unreachable!"
	end
	sizehint!(iv_times, voltssize)
	sizehint!(iv_volts, voltssize)
	sizehint!(iv_currs, voltssize)
	lastact = 1
	iv_is_sweeping[] = true
	if keithley_types[selected_keithley_type] == "MODEL 2400"
		for setvolts in stepvals
			iv_cancel_sweep[] && break
			set_and_measure2400(setvolts, seconds(delay), iv_cancel_sweep)			
		end
	elseif keithley_types[selected_keithley_type] == "MODEL 2470"
		while !iv_cancel_sweep[] && length(iv_volts) != voltssize
			lastact = get_outstanding_data2470(lastact)
		end
	else
		@assert false "Unreachable!"
	end
	iv_is_sweeping[] = false
	errormonitor(Threads.@spawn getevents())
	return
end

function calculate_sweep(min_volts, max_volts, step_voltage, dual)
	if min_volts > max_volts
		min_volts, max_volts = max_volts, min_volts
	end

	firstvolts = min_volts:step_voltage:max_volts
	volts = firstvolts
	if dual
		lastvolts = max_volts:-step_voltage:min_volts
		volts = [firstvolts; lastvolts; min_volts]
	end

	volts
end

function set_and_measure2400(setvolts, sleeptime, interuptref)
	global sleep_interupt_interval
	global Keithley
	global gpiblock
	@lock gpiblock write(Keithley, "SOUR:VOLT $setvolts")

	interuptsleep(sleeptime, interuptref, sleep_interupt_interval)

	meascurr = measvolt = ""
	@lock gpiblock begin
		meascurr = query(Keithley, "MEAS:CURR?")
		measvolt = query(Keithley, "MEAS:VOLT?")
	end
	_, curr = split(meascurr, ',')
	volt, _ = split(measvolt, ',')
	measI = parse(Float64, curr)
	measV = parse(Float64, volt)

	global iv_times, iv_volts, iv_currs
	@lock plotlock begin
		push!(iv_times, now())
		push!(iv_currs, measI)
		push!(iv_volts, measV)
	end
end

function get_outstanding_data2470(lastact)
	global gpiblock
	act = 0
	@lock gpiblock act = query(Keithley, "TRAC:ACT?") |> x->parse(Int, x)
	lastact <= act || return lastact
	
	buff = ""
	@lock gpiblock buff = query(Keithley, "TRAC:DATA? $lastact, $act")
	Imeass = split(buff, ',', keepempty=false) .|> x->parse(Float64, x)

	Vs = [
		begin
			q = ""
			@lock gpiblock q = query(Keithley, "SOUR:CONF:LIST:QUER? \"VoltLinearSweepList\", $i")
			q = split(q, ',', keepempty=false)
			q = filter(q) do elem
				occursin("smu.source.level",elem)
			end[1]
			parse(Float64, split(q,'=')[2])
		end
		for i in lastact:act
	]

	global iv_times, iv_volts, iv_currs
	@lock plotlock begin
		append!(iv_times, fill(now(), size(Imeass)))
		append!(iv_volts, Vs)
		append!(iv_currs, Imeass)
	end
	return lastact+1
end
