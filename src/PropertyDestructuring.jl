module PropertyDestructuring

using ExprTools

export @destructure

function _is_property_assignee(ex)
    Meta.isexpr(ex, :tuple) && (Meta.isexpr(ex.args[1], :parameters) || any(_is_property_assignee, ex.args))
end

function _is_destructure_property_assignment(ex)
    Meta.isexpr(ex, :(=)) && _is_property_assignee(ex.args[1])
end

function _is_destructure_property_for(ex)
    Meta.isexpr(ex, :for) && (
        _is_destructure_property_assignment(ex.args[1]) ||
        Meta.isexpr(ex.args[1], :block) && any(_is_destructure_property_assignment, ex.args[1].args)
    )
end

function _destructure_property_for_multi(ex)
    blk = _destructure(ex.args[2])
    variables = Dict{Symbol, Vector{Any}}()
    in_clauses = Expr(:block)
    for assignment_src in ex.args[1].args
        new_assignee = _deconstruct_assignees!(assignment_src.args[1], variables)
        push!(in_clauses.args, :($new_assignee = $(assignment_src.args[2])))
    end
    assignments = Expr(:block, (
        _to_assignment_ex(sym, var) for sym in keys(variables) for var in variables[sym]
    )...)
    Expr(:for, in_clauses, quote
        $assignments
        $blk
    end)
end

function _destructure_property_for_complex(ex)
    blk = _destructure(ex.args[2])
    new_assignee, variables = _deconstruct_assignees(ex.args[1].args[1])
    src = _destructure(ex.args[1].args[2])
    assignments = Expr(:block, (
        _to_assignment_ex(sym, var) for sym in keys(variables) for var in variables[sym]
    )...)
    :(for $new_assignee in $src
        $assignments
        $blk
    end)
end

function _destructure_property_for(ex)
    # @assert Meta.isexpr(ex, :for) && _is_destructure_property_assignment(ex.args[1])
    Meta.isexpr(ex.args[1], :block) && return _destructure_property_for_multi(ex)
    Meta.isexpr(ex.args[1].args[1], :tuple) && Meta.isexpr(ex.args[1].args[1].args[1], :parameters) || 
        return _destructure_property_for_complex(ex)
    variables = ex.args[1].args[1].args[1].args
    any(Meta.isexpr(v, :(::)) for v in variables) && return _destructure_property_for_complex(ex)
    blk = _destructure(ex.args[2])
    lh = Expr(:tuple, variables...)
    _el = gensym(:el)
    gvars = Expr(:tuple, (:($_el.$var) for var in variables)...)
    src0 = _destructure(ex.args[1].args[2])
    src = :(($gvars for $_el in $(src0)))
    Expr(:for, :($lh = $src), blk)
end

_deconstruct_assignees!(ex, _variables) = ex
function _deconstruct_assignees!(ex::Expr, variables)
    if Meta.isexpr(ex, :tuple) && Meta.isexpr(ex.args[1], :parameters)
        new_symbol = gensym(string(ex))
        variables[new_symbol] = ex.args[1].args
        return new_symbol
    end
    Expr(ex.head, (_deconstruct_assignees!(arg, variables) for arg in ex.args)...)
end

function _deconstruct_assignees(ex)
    variables = Dict{Symbol, Vector{Any}}()
    new_ex = _deconstruct_assignees!(ex, variables)
    (new_ex, variables)
end

_to_assignment_ex(src, var) = :(local $(var) = getproperty($src, $(QuoteNode(var))))
function _to_assignment_ex(src, ex::Expr)
    Meta.isexpr(ex, :(::), 2) || :(local $(ex) = getproperty($src, $(QuoteNode(ex))))  # FALLBACK, will cause Error
    var, _type = ex.args
    :(local $(var)::$(_type) = getproperty($src, $(QuoteNode(var))))
end

function _destructure_property_assignment_complex(ex)
    # @assert _is_destructure_property_assignment(ex)
    new_assignee, variables = _deconstruct_assignees(ex.args[1])
    src = _destructure(ex.args[2])
    assignments = Expr(:block, (_to_assignment_ex(sym, var) for sym in keys(variables) for var in variables[sym])...)
    quote
        $new_assignee = $src
        $assignments
        $src
    end
end

function _destructure_property_assignment(ex)
    # @assert _is_destructure_property_assignment(ex)
    Meta.isexpr(ex.args[1], :tuple) && Meta.isexpr(ex.args[1].args[1], :parameters) || 
        return _destructure_property_assignment_complex(ex)
    variables = ex.args[1].args[1].args
    src = _destructure(ex.args[2])
    assignments = Expr(:block, (_to_assignment_ex(src, var) for var in variables)...)
    quote
        $assignments
        $src
    end
end

# original(inspired by): https://github.com/FluxML/MacroTools.jl/blob/65c55530b63918daac5f041b144c50d4e34e7984/src/utils.jl#L438-L452
splitarg(name::Symbol) = (name, :Any, false, nothing)
function splitarg(arg_expr)
    if Meta.isexpr(arg_expr, :kw)
        # デフォルト値が設定されている場合
        (splitarg(arg_expr.args[1])[1:3]..., arg_expr.args[2])
    elseif Meta.isexpr(arg_expr, :(...))
        # `...` が指定されている場合
        (splitarg(arg_expr.args[1])[1:2]..., true, nothing)
    elseif Meta.isexpr(arg_expr, :(::))
        # 型アノテーションが存在する場合
        _name = length(arg_expr.args) > 1 ? arg_expr.args[1] : nothing
        _type = arg_expr.args[end]
        (_name, _type, false, nothing)
    else
        (arg_expr, :Any, false, nothing)
    end
end

# original(inspired by): https://github.com/FluxML/MacroTools.jl/blob/65c55530b63918daac5f041b144c50d4e34e7984/src/utils.jl#L414-L418
function combinearg(_name, _type, _isslurp, _default)
    ex = isnothing(_name) ? :(::$_type) : :($_name::$_type)
    if _isslurp
        ex = Expr(:(...), ex)
    end
    if !isnothing(_default)
        ex = Expr(:kw, ex, _default)
    end
    ex
end

function _destructure_function_definition(ex)
    # @assert ExprTools.isdef(ex)
    def_dict = ExprTools.splitdef(ex)
    body = def_dict[:body]
    # args = ExprTools.splitarg.(def_dict[:args])
    # if !any(_is_property_assignee, (arg[1] for arg in args))
    assignments = Expr[]
    if haskey(def_dict, :args)
        for (i, arg) in enumerate(def_dict[:args])
            (_name, _type, _slurp, _default) = splitarg(arg)
            if _is_property_assignee(_name)
                newvar = gensym()
                def_dict[:args][i] = combinearg(newvar, _type, _slurp, _default)
                variables = _name.args[1].args
                append!(assignments, [:($(var) = getproperty($newvar, $(QuoteNode(var)))) for var in variables])
            end
        end
    end
    body = Expr(body.head, _destructure.(body.args)...)
    if !isempty(assignments)
        body = Expr(:block, assignments..., body)
    end
    def_dict[:body] = body
    ExprTools.combinedef(def_dict)
end

isdef(ex) = false
isdef(ex::Expr) = !isnothing(ExprTools.splitdef(ex; throw=false))

_destructure(ex) = ex

function _destructure(ex::Expr)
    _is_destructure_property_for(ex) && return _destructure_property_for(ex)
    _is_destructure_property_assignment(ex) && return _destructure_property_assignment(ex)
    isdef(ex) && return _destructure_function_definition(ex)
    Expr(ex.head, _destructure.(ex.args)...)
end

macro destructure(ex::Expr)
    VERSION < v"1.7.0-DEV.364" || return esc(ex)
    esc(_destructure(ex))
end

end
