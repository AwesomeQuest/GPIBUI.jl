
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