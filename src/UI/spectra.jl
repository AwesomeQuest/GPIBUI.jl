
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
			tell_spectra_modal("$(turr+1) TURRET")
		end
		grat::Int32 = (grating÷turret) - 1
		if grating != -1 && @c ig.Combo("Grating", &grat, gratinglist[2turret-1:2turret])
			tell_spectra_modal("$(grat+1) GRATING")
		end
		ig.PopItemWidth()

		ig.PushItemWidth(50UI.WINSCALE)
		BTNSIZE = (40UI.WINSCALE, 15UI.WINSCALE)

		@cstatic set_wavelength::Cfloat = 0.0 begin
			# ig.SetNextItemWidth(20UI.WINSCALE)
			if ig.Button("Set##wave", BTNSIZE)
				tell_spectra_modal(@sprintf "%.1f NM" set_wavelength)
			end
			ig.SameLine()
			@c ig.InputFloat("Set Wavelength [nm]", &set_wavelength, 0.0f0, 0.0f0, "%.1f")
		end

		@cstatic set_speed::Cfloat = 0.0 begin
			# ig.SetNextItemWidth(20UI.WINSCALE)
			if ig.Button("Set##speed", BTNSIZE)
				tell_spectra_modal(@sprintf "%.1f NM/MIN" set_speed)
			end
			ig.SameLine()
			@c ig.InputFloat("Set speed [nm/min]", &set_speed, 0.0f0, 0.0f0, "%.1f")
		end

		@cstatic set_jog::Cfloat = 0.0 begin
			# ig.SetNextItemWidth(20UI.WINSCALE)
			if ig.Button("Set##jog", BTNSIZE)
				tell_spectra_modal(@sprintf "%.2f NM/JOG" set_jog)
			end
			ig.SameLine()
			@c ig.InputFloat("Set jog incr [nm/jog]", &set_jog, 0.0f0, 0.0f0, "%.2f")
		end

		@cstatic gotoval::Cfloat = 0.0 begin
			# ig.SetNextItemWidth(50UI.WINSCALE)
			if ig.Button("GOTO", BTNSIZE)
				tell_spectra_modal(@sprintf "%.2f <GOTO>" gotoval)
			end
			ig.SameLine()
			@c ig.InputFloat("GOTO wavelength", &gotoval, 0.0f0, 0.0f0, "%.2f")
		end

		ig.PopItemWidth()

		for G in gratinglist
			ig.Text(G)
		end

		if ig.BeginPopupModal("Waiting for command to finish", C_NULL, ig.ImGuiWindowFlags_AlwaysAutoResize)
			ig.Text("Hæ, It seems you've pressed a button that takes a while to finish")
			ig.Text("It has been $(round((now() - UI.last_time_button_pressed).ns/1e9, digits=1)) seconds since you pressed the button")
			ig.Text("If you feel it has been too long, you'll need to restart the sepectra pro")
			if isempty(UI.waiting_tasks)
				ig.CloseCurrentPopup()
			else
				S, lastcmd = fetch(UI.waiting_tasks)
				if occursin(r"nm"i, lastcmd)
					setnm = match(r"\d+\.\d+", lastcmd).match |> x->parse(Float64, x)
					ig.Text("Since you sent an 'nm' command, you can expect it to take")
					ig.Text("about $(round(Int, abs(setnm-S.nm)/S.nmmin*60)) seconds for this to finish")
				end
			end
			ig.EndPopup()
		end
	end
	end
end

function tell_spectra_modal(cmd)
	@debug "Spawing tell task"
	Threads.@spawn tell_spectra(cmd)
	UI.last_time_button_pressed = now()

	while isempty(UI.waiting_tasks) yield()	end
	@debug "Opening Popup"
	ig.OpenPopup("Waiting for command to finish")
end
