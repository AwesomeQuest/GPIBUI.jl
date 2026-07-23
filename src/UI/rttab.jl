
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