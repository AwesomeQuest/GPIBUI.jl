using Printf

function menubar()
	if ig.BeginMenuBar()
		if ig.BeginMenu("Device Selection")
			deviceselect()
			ig.EndMenu()
		end

		if ig.BeginMenu("Timestamp Export Mode")
			selected::Int32 = @match DATA.timestamp_mode begin
				:datetime => 1
				:seconds => 2
				:nanoseconds => 3
				_ => -1
			end

			@c ig.RadioButton("DateTime Timestamps", &selected, 1)
			@c ig.RadioButton("Seconds since start of capture", &selected, 2)
			@c ig.RadioButton("Nanoseconds since start of capture", &selected, 3)

			DATA.timestamp_mode = [:datetime, :seconds, :nanoseconds][selected]
			ig.EndMenu()
		end
		ig.EndMenuBar()
	end
end

function deviceselect()
	if isempty(INSTRS.instruments)
		try
			INSTRS.instruments = find_resources(INSTRS.RM)
		catch
			# TODO maybe bad idea
			ResourceManager()
			INSTRS.instruments = find_resources(INSTRS.RM)
		end

		INSTRS.possible_spectra = findfirst(==(GPIBCONFIG[].spectra_name), INSTRS.instruments)
		INSTRS.possible_keithley = findfirst(==(GPIBCONFIG[].keithley_name), INSTRS.instruments)
		if all(!isnothing, (INSTRS.possible_spectra, INSTRS.possible_keithley))
			@debug "Opening Popup"
			ig.OpenPopup("use previous instrs popup") # I put this popup in the menubar function so it will always be drawn
		end
	end
	if ig.BeginPopupModal("use previous instrs popup", C_NULL, ig.ImGuiWindowFlags_AlwaysAutoResize)
		ig.SeparatorText("The previous Instrument addresses seem to still be valid!")
		ig.SeparatorText("Would you like to reuse the following addresses?")
		ig.Text("Keithley = $(GPIBCONFIG[].keithley_name)")
		ig.Text("Spectra = $(GPIBCONFIG[].spectra_name)")
		if ig.Button("Yes")
			INSTRS.selected_keithley = INSTRS.possible_keithley - 1
			INSTRS.selected_spectra = INSTRS.possible_spectra - 1
			connect_devices(INSTRS.instruments, INSTRS.selected_keithley, INSTRS.selected_spectra)
			ig.SetWindowFocus("Plot Window")
			ig.CloseCurrentPopup()
		end
		ig.SameLine(0.0f0, 20.0f0)
		if ig.Button("No")
			ig.CloseCurrentPopup()
		end
		ig.EndPopup()
	end
	


		if ig.Button("Scan for Devices")
			try
			INSTRS.instruments = find_resources(INSTRS.RM)
			catch
				# TODO maybe bad idea
				ResourceManager()
			INSTRS.instruments = find_resources(INSTRS.RM)
			end
		end
	if @c(ig.Combo("Keithley", &INSTRS.selected_keithley, INSTRS.instruments)) && INSTRS.selected_spectra == INSTRS.selected_keithley
			SPECTRA.kill[] = true
			CONNECTED[] = false
		INSTRS.selected_spectra = (INSTRS.selected_spectra + 1) % (length(INSTRS.instruments)-1)
		end
	if @c(ig.Combo("SpectraPro", &INSTRS.selected_spectra, INSTRS.instruments)) && INSTRS.selected_spectra == INSTRS.selected_keithley
			SPECTRA.kill[] = true
			CONNECTED[] = false
		INSTRS.selected_keithley = (INSTRS.selected_keithley + 1) % (length(INSTRS.instruments)-1)
		end

		if ig.Button("Connect")
		connect_devices(INSTRS.instruments, INSTRS.selected_keithley, INSTRS.selected_spectra)
		end

		if KEITHLEY.gpib.connected && SPECTRA.gpib.connected
			ig.SameLine()
			ig.Text("Success!")
		else
			if !KEITHLEY.gpib.connected
				ig.Text("Failed to connect Keithley")
			end
			if !SPECTRA.gpib.connected
				ig.Text("Failed to connect SpectraPro")
			end
		end
	end

function connect_devices(instrs, selected_keithley, selected_spectra)
	connect!(INSTRS.RM, KEITHLEY.gpib, instrs[selected_keithley+1])
	connect!(INSTRS.RM, SPECTRA.gpib, instrs[selected_spectra+1])
	
	id = query(KEITHLEY.gpib, "*IDN?")
	selectedtype = findfirst(KEITHLEY_TYPES) do t
		occursin(t, id)
	end
	if selectedtype !== nothing
		KEITHLEY.selected_type = selectedtype
		CONNECTED[] = true
		SPECTRA.kill[] = false
		errormonitor(Threads.@spawn spectramanager())
		errormonitor(Threads.@spawn spectrastatusmonitor()())
		errormonitor(Threads.@spawn initialize_keithley())
	end
	GPIBCONFIG[].keithley_name = instrs[selected_keithley+1]
	GPIBCONFIG[].spectra_name = instrs[selected_spectra+1]
	ig.MarkIniSettingsDirty()
end


function ivtab()
	@debug_once "inputs"
	ivinputs()
	ig.SameLine()
	ig.BeginGroup()
	flagschecks()
	@debug_once "plot"
	@lock PLOT_LOCK begin
		simpleimplot(
			"I-V Sweep",
			"Voltage [V]", "Current [A]",
			ig.ImVec2(-UI.sidebarwidth,-1),
			DATA.iv_volts, DATA.iv_currs
		)
	end
	ig.EndGroup()
end

function ivinputs()
	ig.BeginGroup()
	cleardatabutton(UI.processes.iv_active, DATA.iv_times, DATA.iv_currs, DATA.iv_volts)
	
	@debug_once "table"
	ig.PushStyleVar(ig.lib.ImGuiStyleVar_CellPadding, (3,3))
	global WINSCALE
	if ig.BeginTable("iv_maxmin_table", 2, 0, (250UI.WINSCALE,50UI.WINSCALE))
		ig.TableSetupColumn("Maximum [A]")
		ig.TableSetupColumn("Minimum [A]")
		ig.TableHeadersRow()
		ig.TableNextRow()
		ig.TableSetColumnIndex(0)
		ig.Text("$(isempty(DATA.iv_currs) ? "NAN" : round(maximum(DATA.iv_currs), sigdigits=5))")
		ig.TableSetColumnIndex(1)
		ig.Text("$(isempty(DATA.iv_currs) ? "NAN" : round(minimum(DATA.iv_currs), sigdigits=5))")
		ig.EndTable()
	end
	ig.PopStyleVar()

	savedatabutton(UI.processes.iv_active, DATA.iv_times, DATA.iv_currs, DATA.iv_volts)

	@debug_once "inputvals"
	sweepinputvals()

	@debug_once "spectra"
	spectracontrols()

	ig.EndGroup()
end

function spectracontrols()
	@cstatic grating::Cint = -1 turret::Cint = -1 begin
	@cstatic gratinglist::Vector{String} = String[] turretlist::Vector{String} = String[] begin
		@debug_once "Init Spectra"
		if grating == -1 && CONNECTED[]
			gratinglist, turretlist = initialize_spectra()
		end

		ig.PushItemWidth(200UI.WINSCALE)
		S = @atomic SPECTRA.status
		if S.fresh
			grating = S.grating
			turret = S.turret

			ig.Text("Wavelength: $(S.nm)")
			ig.Text("Wavelength scan speed: $(S.nmmin)")
			ig.Text("Wavelength jog increment: $(S.nmjog)")
		end

		turr::Int32 = turret - 1
		if grating != -1 && @c ig.Combo("Turret", &turr, turretlist)
			tell_spectra("$(turr+1) TURRET")
		end
		grat::Int32 = (grating÷turret) - 1
		if grating != -1 && @c ig.Combo("Grating", &grat, gratinglist[2turret-1:2turret])
			tell_spectra("$(grat+1) GRATING")
		end
		ig.PopItemWidth()

		ig.PushItemWidth(50UI.WINSCALE)
		BTNSIZE = (40UI.WINSCALE, 15UI.WINSCALE)

		@cstatic set_wavelength::Cfloat = 0.0 begin
			# ig.SetNextItemWidth(20UI.WINSCALE)
			if ig.Button("Set##wave", BTNSIZE)
				tell_spectra(@sprintf "%.1f NM" set_wavelength)
			end
			ig.SameLine()
			@c ig.InputFloat("Set Wavelength [nm]", &set_wavelength)
		end

		@cstatic set_speed::Cfloat = 0.0 begin
			# ig.SetNextItemWidth(20UI.WINSCALE)
			if ig.Button("Set##speed", BTNSIZE)
				tell_spectra(@sprintf "%.1f NM/MIN" set_speed)
			end
			ig.SameLine()
			@c ig.InputFloat("Set speed [nm/min]", &set_speed)
		end

		@cstatic set_jog::Cfloat = 0.0 begin
			# ig.SetNextItemWidth(20UI.WINSCALE)
			if ig.Button("Set##jog", BTNSIZE)
				tell_spectra(@sprintf "%.2f NM/JOG" set_jog)
			end
			ig.SameLine()
			@c ig.InputFloat("Set jog incr [nm/jog]", &set_jog)
		end

		@cstatic gotoval::Cfloat = 0.0 begin
			# ig.SetNextItemWidth(50UI.WINSCALE)
			if ig.Button("GOTO", BTNSIZE)
				tell_spectra(@sprintf "%.2f <GOTO>" gotoval)
			end
			ig.SameLine()
			@c ig.InputFloat("GOTO wavelength", &gotoval)
		end

		ig.PopItemWidth()

		for G in gratinglist
			ig.Text(G)
		end
	end
	end
end

function sweepinputvals()
	@cstatic min_volts::Cdouble		= -1  max_volts::Cdouble	= 1 begin # Nested scopes so
	@cstatic step_voltage::Cdouble	= 0.1 delay::Cdouble		= 0 begin # it's more readable
	@cstatic maxcurrent::Cdouble	= 0.1 dual::Bool			= true begin
		ig.PushItemWidth(90UI.WINSCALE)
		@c ig.InputDouble("Minimum Voltage [V]", &min_volts)
		@c ig.InputDouble("Maximum Voltage [V]", &max_volts)
		@c ig.InputDouble("Step Voltage [V]", &step_voltage)
		if step_voltage < 0 step_voltage = 0 end
		@c ig.InputDouble("Delay [s]", &delay)
		if delay < 0 delay = 0 end

		@c ig.Checkbox("Sweep back and forth", &dual)
		@c ig.InputDouble("Max Current [A]", &maxcurrent)
		ig.PopItemWidth()

		if !UI.processes.iv_active[] && ig.Button("Start Sweep", (250UI.WINSCALE, 30UI.WINSCALE)) && !UI.processes.rt_active[]
			ig.OpenPopup("start_sweep_popup")
		end
		if UI.processes.rt_active[]
			if ig.BeginItemTooltip()
				ig.TextColored((255,0,0,255), "You cannot start a sweep while monitoring")
				ig.EndTooltip()
			end
		end
		if ig.BeginPopup("start_sweep_popup")
			ig.SeparatorText("Are you sure you want to start a sweep?")
			ig.SeparatorText("Starting a sweep will erase the previous sweep from memory.")
			if ig.Button("I'm sure I want to permanently erase data and start a new sweep.")
				UI.processes.iv_cancel[] = false
				errormonitor(
					Threads.@spawn sweep(
						min_volts, max_volts,
						step_voltage, delay,
						maxcurrent, dual)
				)
				ig.CloseCurrentPopup()
			end
			ig.EndPopup()
		end
		if UI.processes.iv_active[] && ig.Button("Stop Sweep", (250UI.WINSCALE, 30UI.WINSCALE))
			UI.processes.iv_cancel[] = true
		end
	end # @static
	end # @static
	end # @static
end

function rttab()
	rtinputs()
	ig.SameLine()
	ig.BeginGroup()
	flagschecks()
	
	@lock PLOT_LOCK begin
		xs::Vector{Float64} = DATA.rt_times .|> x->(x.ns - DATA.rt_times[1].ns)/1e9
		simpleimplot(
			"Real Time Monitor",
			"Time [s]", "Current [A]",
			ig.ImVec2(-UI.sidebarwidth,-1),
			xs, DATA.rt_currs
		)
	end
	ig.EndGroup()
end

function rtinputs()
	ig.BeginGroup()

	cleardatabutton(Ref(false), DATA.rt_times, DATA.rt_currs, DATA.rt_volts)

	ig.PushStyleVar(ig.lib.ImGuiStyleVar_CellPadding, (3,3))
	if ig.BeginTable("iv_maxmin_table", 3, 0, (250UI.WINSCALE,50UI.WINSCALE))
		ig.TableSetupColumn("Maximum [A]")
		ig.TableSetupColumn("Minimum [A]")
		ig.TableSetupColumn("Average [A]")
		ig.TableHeadersRow()
		ig.TableNextRow()
		ig.TableSetColumnIndex(0)
		ig.Text("$(isempty(DATA.rt_currs) ? "NAN" : round(maximum(DATA.rt_currs), sigdigits=5))")
		ig.TableSetColumnIndex(1)
		ig.Text("$(isempty(DATA.rt_currs) ? "NAN" : round(minimum(DATA.rt_currs), sigdigits=5))")
		ig.TableSetColumnIndex(2)
		ig.Text("$(isempty(DATA.rt_currs) ? "NAN" : round(sum(DATA.rt_currs)/length(DATA.rt_currs), sigdigits=5))")
		ig.EndTable()
	end
	ig.PopStyleVar()

	savedatabutton(UI.processes.rt_active, DATA.rt_times, DATA.rt_currs, DATA.rt_volts)

	monitorinputvals()

	ig.EndGroup()
end

function monitorinputvals()
	@cstatic set_volts::Cdouble = 1 samplerate::Cdouble = 0.001 maxcurrent::Cdouble = 0.1 begin
		ig.PushItemWidth(90UI.WINSCALE)
		@c ig.InputDouble("Set Voltage [V]", &set_volts)
		@c ig.InputDouble("Sample rate [s]", &samplerate)
		if samplerate < 0 samplerate = 0 end
		KEITHLEY.config.sample_period = seconds(samplerate)

		@c ig.InputDouble("Max Current [A]", &maxcurrent)
		ig.PopItemWidth()

		if !UI.processes.rt_active[]
			if !isempty(DATA.rt_times) && ig.Button("Resume", (250UI.WINSCALE, 40UI.WINSCALE))
				@goto start_sweep
			elseif isempty(DATA.rt_times) && ig.Button("Start", (250UI.WINSCALE, 40UI.WINSCALE))
				@goto start_sweep
			end
			@goto dont_sweep
			@label start_sweep
			if !UI.processes.iv_active[]
				UI.processes.iv_cancel[] = false
				errormonitor(Threads.@spawn monitor(set_volts, maxcurrent))
			end
			@label dont_sweep
		else
			if ig.Button("Stop", (250UI.WINSCALE, 40UI.WINSCALE))
				UI.processes.rt_cancel[] = true
			end
		end
		if UI.processes.iv_active[]
			if ig.BeginItemTooltip()
				ig.TextColored((255,0,0,255), "You cannot start monitoring during a sweep")
				ig.EndTooltip()
			end
		end
	end
end

function flagschecks()
	@c ig.CheckboxFlags("Fit X-Axis", &UI.xflags, ImPlot.ImPlotAxisFlags_AutoFit)
	ig.SameLine()
	@c ig.CheckboxFlags("Fit Y-Axis", &UI.yflags, ImPlot.ImPlotAxisFlags_AutoFit)
	if (UI.xflags | UI.yflags) & ImPlot.ImPlotAxisFlags_AutoFit == 0
		return
	end
	if (UI.xflags & UI.yflags) & ImPlot.ImPlotAxisFlags_AutoFit != 0
		UI.xflags = UI.xflags & ~ImPlot.ImPlotAxisFlags_RangeFit
		UI.yflags = UI.yflags & ~ImPlot.ImPlotAxisFlags_RangeFit
	else
		ig.SameLine()
		if UI.xflags & ImPlot.ImPlotAxisFlags_AutoFit != 0
			@c ig.CheckboxFlags("Range Fit", &UI.xflags, ImPlot.ImPlotAxisFlags_RangeFit)
		elseif UI.yflags & ImPlot.ImPlotAxisFlags_AutoFit != 0
			@c ig.CheckboxFlags("Range Fit", &UI.yflags, ImPlot.ImPlotAxisFlags_RangeFit)
		else
			@assert false "Unreachable!"
		end
	end
end

function simpleimplot(title, xaxis, yaxis, plot_size, xs, ys)
	if ImPlot.BeginPlot(title, xaxis, yaxis, plot_size)
		ImPlot.SetupAxes(xaxis, yaxis, UI.xflags, UI.yflags)
		if !isempty(xs)
			ImPlot.PlotLine("data", xs, ys)
		end
		ImPlot.EndPlot()
	end
end

function cleardatabutton(notallowref, arrs...)
	global WINSCALE
	global iv_is_sweeping
	global rt_is_monitoring
	if ig.Button("Clear Data", (250UI.WINSCALE, 30UI.WINSCALE)) && !notallowref[]
		ig.OpenPopup("clear data popup")
	end
	if notallowref[]
		if ig.BeginItemTooltip()
			ig.TextColored((255,0,0,255), "You cannot clear data right now")
			ig.EndTooltip()
		end
	end
	if ig.BeginPopup("clear data popup")
		ig.SeparatorText("Are you sure you want to erase the data?")
		ig.SeparatorText("")
		if ig.Button("I'm sure I want to permanently erase data.")
			for arr in arrs
				empty!(arr)
			end
			ig.CloseCurrentPopup()
		end
		ig.EndPopup()
	end
end

function savedatabutton(notallowref, arrs...)
	if ig.Button("Save Data##iv", (250UI.WINSCALE, 30UI.WINSCALE)) && !notallowref[]
		filepath = save_file(;filterlist="csv")
		!isempty(filepath) && savetofile(arrs..., DATA.timestamp_mode, filepath)
	end
	if notallowref[]
		if ig.BeginItemTooltip()
			ig.TextColored((255,0,0,255), "You cannot save data right now")
			ig.EndTooltip()
		end
	end
end

function logs()
	ig.BeginGroup()
	if ig.Button("Get Events")
		errormonitor(Threads.@spawn getevents())
	end

	lst = DATA.event_list |> enumerate |> collect
	@cstatic showinfo = true showwarn = true showerror = true begin
		@c ig.Checkbox("Info", &showinfo)
		ig.SameLine()
		@c ig.Checkbox("Warn", &showwarn)
		ig.SameLine()
		@c ig.Checkbox("Error", &showerror)
		filter!(lst) do ((i, raw))
			msg, type, time = split(raw, ';')
			@match type begin
				"1" => showinfo
				"2" => showwarn
				"4" => showerror
			end
		end
	end

	event_table(lst, DATA.event_list)

	ig.EndGroup()
end

function event_table(list, master)
	tableflags = ig.ImGuiTableFlags_Borders |
		ig.ImGuiTableFlags_RowBg |
		ig.ImGuiTableFlags_SizingFixedFit
	if ig.BeginTable("Event List", 2, tableflags, (UI.sidebarwidth, -1f0))
		ig.TableSetupColumn("msg", ig.ImGuiTableColumnFlags_WidthStretch)
		ig.TableSetupColumn("delete", ig.ImGuiTableColumnFlags_WidthFixed, 30f0)
		for (i,msg) in list
			ig.TableNextRow()
			ig.TableSetColumnIndex(0)
			colw = ig.GetColumnWidth(0)
			ig.PushTextWrapPos(ig.GetCursorPosX() + colw)
			ig.Text(msg)
			ig.PopTextWrapPos()

			ig.TableSetColumnIndex(1)
			ig.PushFont(UI.fontawesome, 12)
			if ig.Button("##listbtn$i")
				popat!(master, i)
			end
			ig.PopFont()
			
		end
		ig.EndTable()
	end
end