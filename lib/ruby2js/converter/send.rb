module Ruby2JS
  class Converter

    # (send nil :puts
    #   (int 1))

    # (attr nil :puts)

    # (sendw nil :puts
    #   (int 1))

    # Note: attr and sendw are only generated by filters.  Attr forces
    # interpretation as an attribute vs a function call with zero parameters.
    # Sendw forces parameters to be placed on separate lines.

    handle :send, :sendw, :attr, :call do |receiver, method, *args|
      ast = @ast

      width = ((ast.type == :sendw && !@nl.empty?) ? 0 : @width)

      # strip '!' and '?' decorations
      method = method.to_s[0..-2] if method =~ /\w[!?]$/

      # three ways to define anonymous functions
      if method == :new and receiver and receiver.children == [nil, :Proc]
        return parse args.first
      elsif not receiver and [:lambda, :proc].include? method
        if method == :lambda
          return parse s(args.first.type, *args.first.children[0..-2],
            s(:autoreturn, args.first.children[-1]))
        else
          return parse args.first
        end
      end

      # call anonymous function
      if [:call, :[]].include? method and receiver and receiver.type == :block 
        t2,m2,*args2 = receiver.children.first.children
        if not t2 and [:lambda, :proc].include? m2 and args2.length == 0
          (@state == :statement ? group(receiver) : parse(receiver))
          put '('; parse_all *args, join: ', '; put ')'
          return
        end
      end

      op_index = operator_index method
      if op_index != -1
        target = args.first 
      end

      # resolve anonymous receivers against rbstack
      receiver ||= @rbstack.map {|rb| rb[method]}.compact.last

      if receiver
        group_receiver = receiver.type == :send &&
          op_index < operator_index( receiver.children[1] ) if receiver
        group_receiver ||= GROUP_OPERATORS.include? receiver.type
        group_receiver = false if receiver.children[1] == :[]
      end

      if target
        group_target = target.type == :send && 
          op_index < operator_index( target.children[1] )
        group_target ||= GROUP_OPERATORS.include? target.type
      end

      if method == :!
        parse s(:not, receiver)

      elsif method == :[]
        parse receiver; put '['; parse_all *args, join: ', '; put ']'

      elsif method == :[]=
        parse receiver; put '['; parse_all *args[0..-2], join: ', '; put '] = '
        parse args[-1]

      elsif [:-@, :+@, :~, '~'].include? method
        put method.to_s[0]; parse receiver

      elsif method == :=~
        parse args.first; put '.test('; parse receiver; put ')'

      elsif method == :!~
        put '!'; parse args.first; put '.test('; parse receiver; put ')'

      elsif method == :<< and args.length == 1 and @state == :statement
        parse receiver; put '.push('; parse args.first; put ')'

      elsif method == :<=>
        raise NotImplementedError, "use of <=>"

      elsif OPERATORS.flatten.include?(method) and not LOGICAL.include?(method)
        (group_receiver ? group(receiver) : parse(receiver))
        put " #{ method } "
        (group_target ? group(target) : parse(target))

      elsif method =~ /=$/
        parse receiver
        put "#{ '.' if receiver }#{ method.to_s.sub(/=$/, ' =') } "
        parse args.first

      elsif method == :new
        if receiver
          # map Ruby's "Regexp" to JavaScript's "Regexp"
          if receiver == s(:const, nil, :Regexp)
            receiver = s(:const, nil, :RegExp)
          end

          # allow a RegExp to be constructed from another RegExp
          if receiver == s(:const, nil, :RegExp)
            if args.first.type == :regexp
              opts = ''
              if args.first.children.last.children.length > 0
                opts = args.first.children.last.children.join
              end

              if args.length > 1
                opts += args.last.children.last
              end

              return parse s(:regexp, *args.first.children[0...-1],
                s(:regopt, *opts.split('').map(&:to_sym)))
            elsif args.first.type == :str
              if args.length == 2 and args[1].type == :str
                opts = args[1].children[0]
              else
                opts = ''
              end
              return parse s(:regexp, args.first,
                s(:regopt, *opts.each_char.map {|c| c}))
            end
          end

          put "new "; parse receiver
          if ast.is_method?
            put '('; parse_all *args, join: ', '; put ')'
          end
        elsif args.length == 1 and args.first.type == :send
          # accommodation for JavaScript like new syntax w/argument list
          parse s(:send, s(:const, nil, args.first.children[1]), :new,
            *args.first.children[2..-1]), @state
        elsif args.length == 1 and args.first.type == :const
          # accommodation for JavaScript like new syntax w/o argument list
          parse s(:attr, args.first, :new), @state
        elsif 
          args.length == 2 and [:send, :const].include? args.first.type and
          args.last.type == :def and args.last.children.first == nil
        then
          # accommodation for JavaScript like new syntax with block
          parse s(:send, s(:const, nil, args.first.children[1]), :new,
            *args.first.children[2..-1], args.last), @state
        else
          raise NotImplementedError, "use of JavaScript keyword new"
        end

      elsif method == :raise and receiver == nil
        if args.length == 1
          put 'throw '; parse args.first
        else
          put 'throw new '; parse args.first; put '('; parse args[1]; put ')'
        end

      elsif method == :typeof and receiver == nil
        put 'typeof '; parse args.first

      else
        if not ast.is_method?
          if receiver
            (group_receiver ? group(receiver) : parse(receiver))
            put ".#{ method }"
          else
            parse ast.updated(:lvasgn, [method]), @state
          end
        elsif args.length > 0 and args.any? {|arg| arg.type == :splat}
          parse s(:send, s(:attr, receiver, method), :apply, 
            (receiver || s(:nil)), s(:array, *args))
        else
          (group_receiver ? group(receiver) : parse(receiver))
          put "#{ '.' if receiver && method}#{ method }"

          if args.length <= 1
            put "("; parse_all *args, join: ', '; put ')'
          else
            compact { puts "("; parse_all *args, join: ",#@ws"; sput ')' }
          end
        end
      end
    end
  end
end
