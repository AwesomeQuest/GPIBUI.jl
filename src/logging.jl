macro debug_once(ex)
    ref = gensym(:debug_once)
    quote
        global $ref
        if !@isdefined($ref)
            $ref = Ref(false)
        end
        if !$ref[]
            $ref[] = true
            @debug $(esc(ex))
        end
    end
end

macro debug_changed(ex)
    ref = gensym(:debug_changed)
    val = gensym(:debug_val)
    quote
        local $val = $(esc(ex))
        global $ref
        if !@isdefined($ref)
            $ref = Ref($val)
        end
        if $ref[] != $val
            $ref[] = $val
            @debug $val
        end
        $val
    end
end
