
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
