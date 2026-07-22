using Match

using ArgParse

function parse_commandline()
	s = ArgParseSettings()

	@add_arg_table! s begin
		"sleep_interupt_time"
			help = "The time interval in milliseconds that the program " *
					"sleeps for between taking samples. It might be more " *
					"performant and accurate to set this value high but " *
					"it also means that you can't cancel a measurement " *
					"in less than `sleep_interupt_time` milliseconds"
		"--debug"
			help = "Enables debug logging"
			action = :store_true
	end
	parsed_args = parse_args(s) # the result is a Dict{String,Any}
	# println("Parsed args:")
	# for (key,val) in parsed_args
	# 	println("  $key  =>  $(repr(val))")
	# end
	return parsed_args
end