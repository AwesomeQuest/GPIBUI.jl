include("spectra.jl")

# global event_list::Vector{String} = []

function getevents()
	CONNECTED[] || nodeviceconnected() || return
	noerr = "No error"

	while true
		output = ""
		@modeswitch KEITHLEY_TYPES[KEITHLEY.selected_type] begin
			"MODEL 2400"
			@lock GPIB_LOCK output = query(KEITHLEY.gpib, "STAT:QUE:NEXT?")
			"MODEL 2470"
			@lock GPIB_LOCK output = query(KEITHLEY.gpib, "SYST:EVEN:NEXT?")
		end
		occursin(noerr, output) && break
		@info output
		push!(DATA.event_list, output)
	end
end

function initialize_keithley()
	CONNECTED[] || nodeviceconnected() || return

	@lock GPIB_LOCK begin
		write(KEITHLEY.gpib, "*RST")
		write(KEITHLEY.gpib, "SOUR:FUNC VOLT")
		write(KEITHLEY.gpib, "SENS:FUNC 'CURR'")
		@modeswitch KEITHLEY_TYPES[KEITHLEY.selected_type] begin
			"MODEL 2400"
			write(KEITHLEY.gpib, "FORM:ELEM VOLT,CURR")
			"MODEL 2470"
			write(KEITHLEY.gpib, ":FORM:ASC:PREC 16")
		end
	end
	errormonitor(Threads.@spawn getevents())
	return
end

function monitor(volts_set, maxcurrent)
	CONNECTED[] || nodeviceconnected() || return

	errormonitor(Threads.@spawn getevents())
	@modeswitch KEITHLEY_TYPES[KEITHLEY.selected_type] begin
		"MODEL 2400"
		@lock GPIB_LOCK write(KEITHLEY.gpib, "SENS:CURR:PROT $(maxcurrent)")
		"MODEL 2470"
		@lock GPIB_LOCK write(KEITHLEY.gpib, "SOUR:VOLT:ILIMIT $(maxcurrent)")
	end
	@lock GPIB_LOCK write(KEITHLEY.gpib, "SOUR:VOLT $(volts_set)")
	@lock GPIB_LOCK write(KEITHLEY.gpib, "OUTP ON")

	@modeswitch KEITHLEY_TYPES[KEITHLEY.selected_type] begin
		"MODEL 2400"
		identity(nothing) # Do nothing
		"MODEL 2470"
		@lock GPIB_LOCK begin
			write(KEITHLEY.gpib, "CURR:AZER ON")
			write(KEITHLEY.gpib, "VOLT:AZER ON")
			query(KEITHLEY.gpib, "MEAS:CURR?")
			query(KEITHLEY.gpib, "MEAS:VOLT?")
			write(KEITHLEY.gpib, "CURR:AZER OFF")
			write(KEITHLEY.gpib, "VOLT:AZER OFF")
		end
	end

	UI.processes.rt_active[] = true
	while !UI.processes.rt_cancel[]
		interuptsleep(KEITHLEY.config.sample_period, UI.processes.rt_cancel, KEITHLEY.config.sleep_interrupt_interval)
		meascurr, measvolt = "", ""
		@lock GPIB_LOCK begin
			meascurr = query(KEITHLEY.gpib, "MEAS:CURR?")
			measvolt = query(KEITHLEY.gpib, "MEAS:VOLT?")
		end
		try
			@modeswitch KEITHLEY_TYPES[KEITHLEY.selected_type] begin
				"MODEL 2400"
				begin
					_, curr = split(meascurr, ',')
					volt, _ = split(measvolt, ',')
					curr = parse(Float64, curr)
					volt = parse(Float64, volt)
				end
				"MODEL 2470"
				begin
					curr = parse(Float64, meascurr)
					volt = parse(Float64, measvolt)
				end
			end
			@lock PLOT_LOCK begin
				push!(DATA.rt_times, now())
				push!(DATA.rt_currs, curr)
				push!(DATA.rt_volts, volt)
			end
		catch e
			@error e
		end
	end
	UI.processes.rt_active[] = false

	@lock GPIB_LOCK write(KEITHLEY.gpib, "OUTP OFF")
	errormonitor(Threads.@spawn getevents())
	return
end

function integrated_2400_sweep(min_volts, max_volts, step_voltage, delay, maxcurrent)
	CONNECTED[] || nodeviceconnected() || return

	@assert length(min_volts:step_voltage:max_volts) > 2500 "Step size too small. Maximum number of points is 2500, got $(length(min_volts:step_voltage:max_volts))"
	
	data = ""
	@lock GPIB_LOCK begin
		write(KEITHLEY.gpib, "*RST")
		write(KEITHLEY.gpib, "SENS:FUNC:CONC OFF")
		write(KEITHLEY.gpib, "SOUR:FUNC VOLT")
		write(KEITHLEY.gpib, "SENS:FUNC 'CURR:DC'")
		write(KEITHLEY.gpib, "SENS:CURR:PROT $(maxcurrent)")
		write(KEITHLEY.gpib, "SOUR:VOLT:STAR $min_volts")
		write(KEITHLEY.gpib, "SOUR:VOLT:STOP $max_volts")
		write(KEITHLEY.gpib, "SOUR:VOLT:STEP $step_voltage")
		write(KEITHLEY.gpib, "SOUR:VOLT:MODE SWE")
		write(KEITHLEY.gpib, "SOUR:SWE:RANG AUTO")
		write(KEITHLEY.gpib, "SOUR:SWE:SPAC LIN")
		write(KEITHLEY.gpib, "TRIG:COUN $(length(min_volts:step_voltage:max_volts))")
		write(KEITHLEY.gpib, "SOUR:DEL $delay")
		write(KEITHLEY.gpib, "SOUR:SWE:DIR UP")
	
		data = query(KEITHLEY.gpib, "READ?")
	end
	data = split(data, ',') .|> x->parse(Float64, x)
	data = reshape(data, 2, :)
	@lock PLOT_LOCK begin
		DATA.iv_volts = @view data[1, :]
		DATA.iv_currs = @view data[2, :]
	end

	
end

function sweep(min_volts, max_volts, step_voltage, delay, maxcurrent, dual)
	CONNECTED[] || nodeviceconnected() || return

	errormonitor(Threads.@spawn getevents())
	@lock GPIB_LOCK begin
		@modeswitch KEITHLEY_TYPES[KEITHLEY.selected_type] begin
			"MODEL 2400"
			write(KEITHLEY.gpib, "SENS:CURR:PROT $(maxcurrent)")
			"MODEL 2470"
			begin
				write(KEITHLEY.gpib, "SOUR:VOLT:ILIMIT $(maxcurrent)")
				D = dual ? "ON" : "OFF"
				write(KEITHLEY.gpib, "SOUR:SWE:VOLT:LIN:STEP $min_volts, $max_volts, $step_voltage, $delay, 1, AUTO, ON, $D")
			end
		end
	end

	@lock plotlock begin
		empty!(DATA.iv_times)
		empty!(DATA.iv_volts)
		empty!(DATA.iv_currs)
	end
	
	@lock GPIB_LOCK begin
		write(KEITHLEY.gpib, "SOUR:VOLT 0")
		write(KEITHLEY.gpib, "OUTP ON")
		@modeswitch KEITHLEY_TYPES[KEITHLEY.selected_type] begin
			"MODEL 2400"
			identity(nothing) # Do nothing
			"MODEL 2470"
			write(KEITHLEY.gpib, "INIT")
		end
	end
	stepvals = calculate_sweep(min_volts, max_volts, step_voltage, dual)
	@modeswitch KEITHLEY_TYPES[KEITHLEY.selected_type] begin
		"MODEL 2400"
		voltssize = length(stepvals)
		"MODEL 2470"
		begin
			voltssize = ""
			@lock GPIB_LOCK voltssize = query(KEITHLEY.gpib, "SOUR:CONF:LIST:SIZE? \"VoltLinearSweepList\"")
			voltssize = parse(Int, voltssize)
		end
	end
	sizehint!(DATA.iv_times, voltssize)
	sizehint!(DATA.iv_volts, voltssize)
	sizehint!(DATA.iv_currs, voltssize)
	lastact = 1
	UI.processes.iv_active[] = true
	@modeswitch KEITHLEY_TYPES[KEITHLEY.selected_type] begin
		"MODEL 2400"
		for setvolts in stepvals
			UI.processes.iv_cancel[] && break
			set_and_measure2400(setvolts, seconds(delay), UI.processes.iv_cancel)			
		end
		"MODEL 2470"
		while !UI.processes.iv_cancel[] && length(iv_volts) != voltssize
			lastact = get_outstanding_data2470(lastact)
		end
	end
	UI.processes.iv_active[] = false
	errormonitor(Threads.@spawn getevents())
	return
end

function calculate_sweep(min_volts, max_volts, step_voltage, dual)
	if sign(step_voltage) != sign(max_volts-min_volts)
	    step_voltage = -step_voltage
	end

	firstvolts = collect(min_volts:step_voltage:max_volts)
	volts = firstvolts
	if dual
		lastvolts = collect(max_volts:-step_voltage:min_volts)
		volts = [firstvolts; lastvolts; min_volts]
	end

	volts
end

function set_and_measure2400(setvolts, sleeptime, interuptref)
	@lock GPIB_LOCK write(KEITHLEY.gpib, "SOUR:VOLT $setvolts")

	interuptsleep(sleeptime, interuptref, KEITHLEY.config.sleep_interrupt_interval)

	meascurr = measvolt = ""
	@lock GPIB_LOCK begin
		meascurr = query(KEITHLEY.gpib, "MEAS:CURR?")
		measvolt = query(KEITHLEY.gpib, "MEAS:VOLT?")
	end
	_, curr = split(meascurr, ',')
	volt, _ = split(measvolt, ',')
	measI = parse(Float64, curr)
	measV = parse(Float64, volt)

	@lock PLOT_LOCK begin
		push!(DATA.iv_times, now())
		push!(DATA.iv_currs, measI)
		push!(DATA.iv_volts, measV)
	end
end

function get_outstanding_data2470(lastact)
	act = 0
	@lock GPIB_LOCK act = query(KEITHLEY.gpib, "TRAC:ACT?") |> x->parse(Int, x)
	lastact <= act || return lastact
	
	buff = ""
	@lock GPIB_LOCK buff = query(KEITHLEY.gpib, "TRAC:DATA? $lastact, $act")
	Imeass = split(buff, ',', keepempty=false) .|> x->parse(Float64, x)

	Vs = [
		begin
			q = ""
			@lock GPIB_LOCK q = query(KEITHLEY.gpib, "SOUR:CONF:LIST:QUER? \"VoltLinearSweepList\", $i")
			q = split(q, ',', keepempty=false)
			q = filter(q) do elem
				occursin("smu.source.level",elem)
			end
			q = q[1]
			parse(Float64, split(q,'=')[2])
		end
		for i in lastact:act
	]

	@lock PLOT_LOCK begin
		append!(DATA.iv_times, fill(now(), size(Imeass)))
		append!(DATA.iv_volts, Vs)
		append!(DATA.iv_currs, Imeass)
	end
	return lastact+1
end
