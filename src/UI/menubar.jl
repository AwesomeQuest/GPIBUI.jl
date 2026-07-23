
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