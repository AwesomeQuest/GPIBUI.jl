
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