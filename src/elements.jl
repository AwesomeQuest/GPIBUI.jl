
function menubar()
	if ig.BeginMenuBar()
		if ig.BeginMenu("Device Selection")
			@cstatic instrs = String[] selected_keithley::Cint = 0 selected_spectra::Cint = 0 begin
				if ig.Button("Scan for Devices")
					global RM
					RM = ResourceManager()
					instrs = find_resources(RM)
				end
				if @c(ig.Combo("Keithley", &selected_keithley, instrs)) && selected_spectra == selected_keithley
					global is_connected, kill_manager
					kill_manager[] = true
					is_connected = false
					selected_spectra = (selected_spectra + 1) % (length(instrs)-1)
				end
				if @c(ig.Combo("SpectraPro", &selected_spectra, instrs)) && selected_spectra == selected_keithley
					global is_connected, kill_manager
					kill_manager[] = true
					is_connected = false
					selected_keithley = (selected_keithley + 1) % (length(instrs)-1)
				end
				global RM
				global Keithley
				global Spectra
				if ig.Button("Connect")
					connect!(RM, Keithley, instrs[selected_keithley+1])
					connect!(RM, Spectra, instrs[selected_spectra+1])
					
					id = query(Keithley, "*IDN?")
					selectedtype = findfirst(keithley_types) do t
						occursin(t, id)
					end
					if selectedtype !== nothing
						global selected_keithley_type
						selected_keithley_type = selectedtype
						global is_connected
						is_connected = true
						global kill_manager
						kill_manager[] = false
						errormonitor(Threads.@spawn spectramanager())
						initialize_keithley()
					end


				end
				if Keithley.connected && Spectra.connected
					ig.SameLine()
					ig.Text("Success!")
				else
					if !Keithley.connected
						ig.Text("Failed to connect Keithley")
					end
					if !Spectra.connected
						ig.Text("Failed to connect SpectraPro")
					end
				end
			end
			ig.EndMenu()
		end

		if ig.BeginMenu("Timestamp Export Mode")
			global timestamp_mode
			selected::Int32 = @match timestamp_mode begin
				:datetime => 1
				:seconds => 2
				:nanoseconds => 3
				_ => -1
			end

			@c ig.RadioButton("DateTime Timestamps", &selected, 1)
			@c ig.RadioButton("Seconds since start of capture", &selected, 2)
			@c ig.RadioButton("Nanoseconds since start of capture", &selected, 3)

			global timestamp_mode
			timestamp_mode = [:datetime, :seconds, :nanoseconds][selected]
			ig.EndMenu()
		end


		ig.EndMenuBar()
	end
end


function ivtab()
	@debug_once "inputs"
	ivinputs()
	ig.SameLine()
	ig.BeginGroup()
	flagschecks()
	@debug_once "plot"
	@lock plotlock begin
		simpleimplot(
			"I-V Sweep",
			"Voltage [V]", "Current [A]",
			ig.ImVec2(-sidebarwidth,-1),
			iv_volts, iv_currs
		)
	end
	ig.EndGroup()
end

function ivinputs()
	ig.BeginGroup()
	global iv_times
	global iv_currs
	global iv_volts
	cleardatabutton(iv_times, iv_currs, iv_volts)
	
	@debug_once "table"
	ig.PushStyleVar(ig.lib.ImGuiStyleVar_CellPadding, (3,3))
	global WINSCALE
	if ig.BeginTable("iv_maxmin_table", 2, 0, (250WINSCALE,50WINSCALE))
		ig.TableSetupColumn("Maximum [A]")
		ig.TableSetupColumn("Minimum [A]")
		ig.TableHeadersRow()
		ig.TableNextRow()
		ig.TableSetColumnIndex(0)
		ig.Text("$(isempty(iv_currs) ? "NAN" : round(maximum(iv_currs), sigdigits=5))")
		ig.TableSetColumnIndex(1)
		ig.Text("$(isempty(iv_currs) ? "NAN" : round(minimum(iv_currs), sigdigits=5))")
		ig.EndTable()
	end
	ig.PopStyleVar()

	global iv_times
	global iv_currs
	global iv_volts
	savedatabutton(iv_times, iv_currs, iv_volts)

	@debug_once "inputvals"
	sweepinputvals()

	@debug_once "spectra"
	spectracontrols()

	ig.EndGroup()
end

function spectracontrols()
	@cstatic scan_speed	= Cdouble(100) curr_nm = Cdouble(0.0) begin
	@cstatic jog_speed	= Cdouble(100) grating = Cint(-1) turret = Cint(-1) begin
	@cstatic gratinglist::Vector{String} = String[] turretlist::Vector{String} = String[] begin
		@debug_once "Init Spectra"
		global is_connected
		if grating == -1 && is_connected
			nm, nmmin, nmjog, selectedG, selectedT, gratinglist, turretlist = initialize_spectra()
			curr_nm = parse(Float64, nm)
			scan_speed = parse(Float64, nmmin)
			jog_speed = parse(Float64, filter(isdigit, nmjog))
			grating = parse(Int32, selectedG)
			turret = parse(Int32, selectedT)
		end

		global WINSCALE
		ig.PushItemWidth(200WINSCALE)
		turr::Int32 = turret - 1
		if grating != -1 && @c ig.Combo("Turret", &turr, turretlist)
			turret = turr + 1
		end
		grat::Int32 = grating - 1
		if grating != -1 && @c ig.Combo("Grating", &grat, gratinglist[2turret-1:2turret])
			grating = grat + 1
		end
		ig.PopItemWidth()




		for G in gratinglist
			ig.Text(G)
		end
		for T in turretlist
			ig.Text(T)
		end


	end
	end
	end
end

function sweepinputvals()
	@cstatic min_volts		= Cdouble(-1)  max_volts = Cdouble(1) begin # Nested scopes so
	@cstatic step_voltage	= Cdouble(0.1) delay	 = Cdouble(0) begin # it's more readable
	@cstatic maxcurrent		= Cdouble(0.1) dual		 = true begin
		global WINSCALE
		ig.PushItemWidth(90WINSCALE)
		@c ig.InputDouble("Minimum Voltage [V]", &min_volts)
		@c ig.InputDouble("Maximum Voltage [V]", &max_volts)
		@c ig.InputDouble("Step Voltage [V]", &step_voltage)
		if step_voltage < 0 step_voltage = 0 end
		@c ig.InputDouble("Delay [s]", &delay)
		if delay < 0 delay = 0 end

		@c ig.Checkbox("Sweep back and forth", &dual)
		@c ig.InputDouble("Max Current [A]", &maxcurrent)
		ig.PopItemWidth()

		global iv_is_sweeping
		global iv_cancel_sweep
		global rt_is_monitoring
		global WINSCALE
		if !iv_is_sweeping[] && ig.Button("Start Sweep", (250WINSCALE, 30WINSCALE)) && !rt_is_monitoring[]
			ig.OpenPopup("start_sweep_popup")
		end
		if rt_is_monitoring[]
			if ig.BeginItemTooltip()
				ig.TextColored((255,0,0,255), "You cannot start a sweep while monitoring")
				ig.EndTooltip()
			end
		end
		if ig.BeginPopup("start_sweep_popup")
			ig.SeparatorText("Are you sure you want to start a sweep?")
			ig.SeparatorText("Starting a sweep will erase the previous sweep from memory.")
			if ig.Button("I'm sure I want to permanently erase data and start a new sweep.")
				iv_cancel_sweep[] = false
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
		global iv_cancel_sweep
		if iv_is_sweeping[] && ig.Button("Stop Sweep", (250WINSCALE, 30WINSCALE))
			iv_cancel_sweep[] = true
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
	
	@lock plotlock begin
		xs::Vector{Float64} = rt_times .|> x->x.ns/1e9
		simpleimplot(
			"Real Time Monitor",
			"Time [s]", "Current [A]",
			ig.ImVec2(-sidebarwidth,-1),
			xs, rt_currs
		)
	end
	ig.EndGroup()
end

function rtinputs()
	ig.BeginGroup()

	global rt_times
	global rt_currs
	global rt_volts
	cleardatabutton(rt_times, rt_currs, rt_volts)
	
	ig.PushStyleVar(ig.lib.ImGuiStyleVar_CellPadding, (3,3))
	global WINSCALE
	if ig.BeginTable("iv_maxmin_table", 3, 0, (250WINSCALE,50WINSCALE))
		ig.TableSetupColumn("Maximum [A]")
		ig.TableSetupColumn("Minimum [A]")
		ig.TableSetupColumn("Average [A]")
		ig.TableHeadersRow()
		ig.TableNextRow()
		ig.TableSetColumnIndex(0)
		ig.Text("$(isempty(rt_currs) ? "NAN" : round(maximum(rt_currs), sigdigits=5))")
		ig.TableSetColumnIndex(1)
		ig.Text("$(isempty(rt_currs) ? "NAN" : round(minimum(rt_currs), sigdigits=5))")
		ig.TableSetColumnIndex(2)
		ig.Text("$(isempty(rt_currs) ? "NAN" : round(sum(rt_currs)/length(rt_currs), sigdigits=5))")
		ig.EndTable()
	end
	ig.PopStyleVar()

	global rt_times
	global rt_currs
	global rt_volts
	savedatabutton(rt_times, rt_currs, rt_volts)

	monitorinputvals()

	ig.EndGroup()
end

function monitorinputvals()
	@cstatic set_volts=Cdouble(1) samplerate=Cdouble(0.001) maxcurrent=Cdouble(0.1) begin
		ig.PushItemWidth(90WINSCALE)
		@c ig.InputDouble("Set Voltage [V]", &set_volts)
		@c ig.InputDouble("Sample rate [s]", &samplerate)
		if samplerate < 0 samplerate = 0 end
		global rt_sample_period
		rt_sample_period = seconds(samplerate)

		@c ig.InputDouble("Max Current [A]", &maxcurrent)
		ig.PopItemWidth()

		global rt_is_monitoring
		global rt_cancel_monitor
		global iv_is_sweeping
		global WINSCALE
		if !rt_is_monitoring[]
			global rt_times
			if !isempty(rt_times) && ig.Button("Resume", (250WINSCALE, 40WINSCALE))
				@goto start_sweep
			elseif isempty(rt_times) && ig.Button("Start", (250WINSCALE, 40WINSCALE))
				@goto start_sweep
			end
			@goto dont_sweep
			@label start_sweep
			if !iv_is_sweeping[]
				rt_cancel_monitor[] = false
				errormonitor(Threads.@spawn monitor(set_volts, maxcurrent))
			end
			@label dont_sweep
		else
			if ig.Button("Stop", (250WINSCALE, 40WINSCALE))
				rt_cancel_monitor[] = true
			end
		end
		if iv_is_sweeping[]
			if ig.BeginItemTooltip()
				ig.TextColored((255,0,0,255), "You cannot start monitoring during a sweep")
				ig.EndTooltip()
			end
		end
	end
end

function flagschecks()
	global xflags
	global yflags
	@c ig.CheckboxFlags("Fit X-Axis", &xflags, ImPlot.ImPlotAxisFlags_AutoFit)
	ig.SameLine()
	@c ig.CheckboxFlags("Fit Y-Axis", &yflags, ImPlot.ImPlotAxisFlags_AutoFit)
	if (xflags | yflags) & ImPlot.ImPlotAxisFlags_AutoFit != 0
		if (xflags & yflags) & ImPlot.ImPlotAxisFlags_AutoFit != 0
			xflags = xflags & ~ImPlot.ImPlotAxisFlags_RangeFit
			yflags = yflags & ~ImPlot.ImPlotAxisFlags_RangeFit
		else
			ig.SameLine()
			if xflags & ImPlot.ImPlotAxisFlags_AutoFit != 0
				@c ig.CheckboxFlags("Range Fit", &xflags, ImPlot.ImPlotAxisFlags_RangeFit)
			elseif yflags & ImPlot.ImPlotAxisFlags_AutoFit != 0
				@c ig.CheckboxFlags("Range Fit", &yflags, ImPlot.ImPlotAxisFlags_RangeFit)
			else
				@assert false "Unreachable!"
			end
		end
	end
end

function simpleimplot(title, xaxis, yaxis, plot_size, xs, ys)
	global WINSCALE
	global sidebarwidth
	if ImPlot.BeginPlot(title, xaxis, yaxis, plot_size)
		global xflags
		global yflags
		ImPlot.SetupAxes(xaxis, yaxis, xflags, yflags)
		if !isempty(xs)
			ImPlot.PlotLine("data", xs, ys)
		end
		ImPlot.EndPlot()
	end
end

function cleardatabutton(arrs...)
	global WINSCALE
	global iv_is_sweeping
	global rt_is_monitoring
	if ig.Button("Clear Data", (250WINSCALE, 30WINSCALE)) && !(iv_is_sweeping[] || rt_is_monitoring[])
		ig.OpenPopup("clear data popup")
	end
	if iv_is_sweeping[] || rt_is_monitoring[]
		if ig.BeginItemTooltip()
			ig.TextColored((255,0,0,255), "You cannot clear data during a sweep or while monitoring")
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

function savedatabutton(arrs...)
	global timestamp_mode
	global iv_is_sweeping
	global rt_is_monitoring
	if ig.Button("Save Data##iv", (250WINSCALE, 30WINSCALE)) && !(iv_is_sweeping[] || rt_is_monitoring[])
		filepath = save_file(;filterlist="csv")
		!isempty(filepath) && savetofile(arrs..., timestamp_mode, filepath)
	end
	if iv_is_sweeping[] || rt_is_monitoring[]
		if ig.BeginItemTooltip()
			ig.TextColored((255,0,0,255), "You cannot save data during a sweep or while monitoring")
			ig.EndTooltip()
		end
	end
end

function logs()
	ig.BeginGroup()
	if ig.Button("Get Events")
		errormonitor(Threads.@spawn getevents())
	end

	global event_list
	lst = event_list |> enumerate |> collect
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

	event_table(lst, event_list)

	ig.EndGroup()
end

function event_table(list, master)
	global sidebarwidth
	global WINSCALE
	tableflags = ig.ImGuiTableFlags_Borders |
		ig.ImGuiTableFlags_RowBg |
		ig.ImGuiTableFlags_SizingFixedFit
	if ig.BeginTable("Event List", 2, tableflags, (sidebarwidth, -1f0))
		ig.TableSetupColumn("msg", ig.ImGuiTableColumnFlags_WidthStretch)
		ig.TableSetupColumn("delete", ig.ImGuiTableColumnFlags_WidthFixed, 30f0)
		for (i,msg) in list
			ig.TableNextRow()
			ig.TableSetColumnIndex(0)
			colw = ig.GetColumnWidth(0)
			ig.PushTextWrapPos(ig.GetCursorPosX() + colw)
			ig.Text(msg)
			ig.PopTextWrapPos()

			global fontawesome
			ig.TableSetColumnIndex(1)
			ig.PushFont(fontawesome, 12)
			if ig.Button("##listbtn$i")
				popat!(master, i)
			end
			ig.PopFont()
			
		end
		ig.EndTable()
	end
end