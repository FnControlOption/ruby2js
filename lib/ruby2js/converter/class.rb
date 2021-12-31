module Ruby2JS
  class Converter

    # (class
    #   (const nil :A)
    #   (const nil :B)
    #   (...)

    # NOTE: :prop and :method macros are defined at the bottom of this file

    # NOTE: class_extend is not generated by the parser, but instead produced
    #       when ++class is encountered; it signals that this construct is
    #       meant to extend an already existing JavaScrpt class.
    #
    #       class_hash is an anonymous class as a value in a hash; the
    #       name has already been output so should be ignored other than
    #       in determining the namespace.
    #
    #       class_module is a module that to be re-processed by this handler
    #       given the similarity between the two structures.

    handle :class, :class_hash, :class_extend, :class_module do |name, inheritance, *body|
      extend = @namespace.enter(name) unless @ast.type == :class_module

      if !%i(class class_hash).include?(@ast.type) or extend
        init = nil
      else
        if es2015 and not extend
          if @ast.type == :class_hash
            parse @ast.updated(:class2, [nil, *@ast.children[1..-1]])
          else
            parse @ast.updated(:class2)
          end
          @namespace.leave unless @ast.type == :class_module
          return
        end

        if inheritance
          parent = @namespace.find(inheritance)&.[](:constructor)
          init = s(:def, :initialize, parent || s(:args), s(:zsuper))
        else
          init = s(:def, :initialize, s(:args), nil)
        end
      end

      body.compact!

      if body.length == 1 and body.first.type == :begin
        body = body.first.children.dup 
      end

      body.compact!
      visible = @namespace.getOwnProps
      body.map! do |m| 
        if \
          @ast.type == :class_module and m.type == :defs and
          m.children.first == s(:self)
        then
          m = m.updated(:def, m.children[1..-1])
        end

        node = if %i(def defm deff).include? m.type
          if m.children.first == :initialize and !visible[:initialize]
            # constructor: remove from body and overwrite init function
            init = m
            nil
          elsif m.children.first =~ /=/
            # property setter
            sym = :"#{m.children.first.to_s[0..-2]}"
            s(:prop, s(:attr, name, :prototype), sym =>
                {enumerable: s(:true), configurable: s(:true),
                 set: s(:defm, nil, *m.children[1..-1])})
          else

            if not m.is_method?
              visible[m.children[0]] = s(:self)

              # property getter
              s(:prop, s(:attr, name, :prototype), m.children.first =>
                  {enumerable: s(:true), configurable: s(:true),
                   get: s(:defm, nil, m.children[1],
                     m.updated(:autoreturn, m.children[2..-1]))})
            else
              visible[m.children[0]] = s(:autobind, s(:self))

              # method: add to prototype
              s(:method, s(:attr, name, :prototype),
                :"#{m.children[0].to_s.chomp('!')}=",
                s(:defm, nil, *m.children[1..-1]))
            end
          end

        elsif %i(defs defp).include? m.type and m.children.first == s(:self)
          if m.children[1] =~ /=$/
            # class property setter
            s(:prop, name, m.children[1].to_s[0..-2] =>
                {enumerable: s(:true), configurable: s(:true),
                 set: s(:def, nil, *m.children[2..-1])})
          elsif m.children[2].children.length == 0 and
            m.children[1] !~ /!/ and m.loc and m.loc.name and
            m.loc.name.source_buffer.source[m.loc.name.end_pos] != '('

            # class property getter
            s(:prop, name, m.children[1].to_s =>
                {enumerable: s(:true), configurable: s(:true),
                 get: s(:block, s(:send, nil, :proc), m.children[2],
                   m.updated(:autoreturn, m.children[3..-1]))})
          else
            # class method definition: add to prototype
            s(:prototype, s(:send, name, "#{m.children[1]}=",
              s(:defm, nil, *m.children[2..-1])))
          end

        elsif m.type == :send and m.children.first == nil
          if m.children[1] == :attr_accessor
            m.children[2..-1].map do |child_sym|
              var = child_sym.children.first
              visible[var] = s(:self)
              s(:prop, s(:attr, name, :prototype), var =>
                  {enumerable: s(:true), configurable: s(:true),
                   get: s(:block, s(:send, nil, :proc), s(:args), 
                     s(:return, s(:ivar, :"@#{var}"))),
                   set: s(:block, s(:send, nil, :proc), s(:args, s(:arg, var)), 
                     s(:ivasgn, :"@#{var}", s(:lvar, var)))})
            end
          elsif m.children[1] == :attr_reader
            m.children[2..-1].map do |child_sym|
              var = child_sym.children.first
              visible[var] = s(:self)
              s(:prop, s(:attr, name, :prototype), var =>
                  {get: s(:block, s(:send, nil, :proc), s(:args), 
                    s(:return, s(:ivar, :"@#{var}"))),
                   enumerable: s(:true),
                   configurable: s(:true)})
            end
          elsif m.children[1] == :attr_writer
            m.children[2..-1].map do |child_sym|
              var = child_sym.children.first
              visible[var] = s(:self)
              s(:prop, s(:attr, name, :prototype), var =>
                  {set: s(:block, s(:send, nil, :proc), s(:args, s(:arg, var)), 
                    s(:ivasgn, :"@#{var}", s(:lvar, var))),
                   enumerable: s(:true),
                   configurable: s(:true)})
            end
          elsif m.children[1] == :include
            s(:send, s(:block, s(:send, nil, :lambda), s(:args),
              s(:begin, *m.children[2..-1].map {|modname|
                @namespace.defineProps @namespace.find(modname)
                s(:for, s(:lvasgn, :$_), modname,
                  s(:send, s(:attr, name, :prototype), :[]=,
                    s(:lvar, :$_), s(:send, modname, :[], s(:lvar, :$_))))
              })), :[])
          elsif [:private, :protected, :public].include? m.children[1]
            raise Error.new("class #{m.children[1]} is not supported", @ast)
          else
            # class method call
            s(:send, name, *m.children[1..-1])
          end

        elsif m.type == :block and m.children.first.children.first == nil
          # class method calls passing a block
          s(:block, s(:send, name, *m.children.first.children[1..-1]), 
            *m.children[1..-1])
        elsif [:send, :block].include? m.type
          # pass through method calls with non-nil targets
          m
        elsif m.type == :lvasgn
          # class variable
          s(:send, name, "#{m.children[0]}=", *m.children[1..-1])
        elsif m.type == :cvasgn
          # class variable
          s(:send, name, "_#{m.children[0][2..-1]}=", *m.children[1..-1])
        elsif m.type == :send and m.children[0].type == :cvar
          s(:send, s(:attr, name, "_#{m.children[0].children[0][2..-1]}"),
            *m.children[1..-1])
        elsif m.type == :casgn and m.children[0] == nil
          # class constant
          visible[m.children[1]] = name
          s(:send, name, "#{m.children[1]}=", *m.children[2..-1])
        elsif m.type == :alias
          s(:send, s(:attr, name, :prototype),
            "#{m.children[0].children.first}=", 
            s(:attr, s(:attr, name, :prototype), m.children[1].children.first))
        elsif m.type == :class or m.type == :module
          innerclass_name = m.children.first
          if innerclass_name.children.first
            innerclass_name = innerclass_name.updated(nil,
              [s(:attr, name, innerclass_name.children[0].children.last),
                innerclass_name.children[1]])
          else
            innerclass_name = innerclass_name.updated(nil,
              [name, innerclass_name.children[1]])
          end
          m.updated(nil, [innerclass_name, *m.children[1..-1]])
        elsif @ast.type == :class_module
          m
        elsif m.type == :defineProps
          @namespace.defineProps m.children.first
          visible.merge! m.children.first
          nil
        else
          raise Error.new("class #{ m.type } not supported", @ast)
        end

        # associate comments
        if node and @comments[m]
          if Array === node
            node[0] = m.updated(node.first.type, node.first.children)
            @comments[node.first] = @comments[m]
          else
            node = m.updated(node.type, node.children)
            @comments[node] = @comments[m]
          end
        end

        node
      end

      body.flatten!

      # merge property definitions
      combine_properties(body)

      if inheritance and (@ast.type != :class_extend and !extend)
        body.unshift s(:send, name, :prototype=, 
          s(:send, s(:const, nil, :Object), :create,
            s(:attr, inheritance, :prototype))),
          s(:send, s(:attr, name, :prototype), :constructor=, name)
      else
        body.compact!

        # look for first sequence of instance methods and properties
        methods = 0
        start = 0
        body.each do |node|
          if (node.type == :method or (node.type == :prop and es2015)) and
            node.children[0].type == :attr and
            node.children[0].children[1] == :prototype
            methods += 1
          elsif node.type == :class and @ast.type == :class_module and es2015
            methods += 1 if node.children.first.children.first == name
          elsif node.type == :module and @ast.type == :class_module
            methods += 1 if node.children.first.children.first == name
          elsif methods == 0
            start += 1
          else
            break
          end
        end

        # collapse sequence to a single assignment
        if \
          @ast.type == :class_module or methods > 1 or 
          body[start]&.type == :prop
        then
          pairs = body[start...start + methods].map do |node|
            if node.type == :method
              replacement = node.updated(:pair, [
                s(:str, node.children[1].to_s.chomp('=')),
                node.children[2]])
            elsif node.type == :class and node.children.first.children.first == name
              sym = node.children.first.children.last
              replacement = s(:pair, s(:sym, sym),
                s(:class_hash, s(:const, nil, sym), nil, node.children.last))
            elsif node.type == :module and node.children.first.children.first == name
              sym = node.children.first.children.last
              replacement = s(:pair, s(:sym, sym),
                s(:module_hash, s(:const, nil, sym), node.children.last))
            else
              replacement = node.children[1].map do |prop, descriptor|
                node.updated(:pair, [s(:prop, prop), descriptor])
              end
            end

            if @comments[node]
              if Array === replacement
                @comments[replacement.first] = @comments[node]
              else
                @comments[replacement] = @comments[node]
              end
            end
            replacement
          end

          if @ast.type == :class_module
            start = 0 if methods == 0
            if name
              body[start...start + methods] =
                s(:casgn, *name.children, s(:hash, *pairs.flatten))
            else
              body[start...start + methods] = s(:hash, *pairs.flatten)
            end
          elsif @ast.type == :class_extend or extend
            body[start...start + methods] =
              s(:assign, body[start].children.first, s(:hash, *pairs.flatten))
          else
            body[start...start + methods] =
              s(:send, name, :prototype=, s(:hash, *pairs.flatten))
          end

        elsif (@ast.type == :class_extend or extend) and methods > 1

          pairs = body[start...start + methods].map do |node|
            node.updated(:pair, [
              s(:sym, node.children[1].to_s[0..-2]), node.children[2]])
          end

          body[start...start + methods] =
            s(:assign, body[start].children.first, s(:hash, *pairs))
        end
      end

      # prepend constructor
      if init
        constructor = init.updated(:constructor, [name, *init.children[1..-1]])
        visible[:constructor] = init.children[1]

        if @ast.type == :class_extend or extend
          if es2015
            constructor = s(:masgn, s(:mlhs, 
              s(:attr, s(:casgn, *name.children, constructor), :prototype)), 
              s(:array, s(:attr, name, :prototype)))
          else
            constructor = s(:send, s(:block, s(:send, nil, :proc),
              s(:args, s(:shadowarg, :$_)), s(:begin,
                s(:gvasgn, :$_, s(:attr, name, :prototype)),
                s(:send, s(:casgn, *name.children, constructor),
                  :prototype=, s(:gvar, :$_)))), :[])
          end
        end

        @comments[constructor] = @comments[init] unless @comments[init].empty?
        body.unshift constructor
      end

      begin
        # save class name
        class_name, @class_name = @class_name, name
        class_parent, @class_parent = @class_parent, inheritance

        # inhibit ivar substitution within a class definition.  See ivars.rb
        ivars, self.ivars = self.ivars, nil

        # add locally visible interfaces to rbstack.  See send.rb, const.rb
        @rbstack.push visible
        @rbstack.last.merge!(@namespace.find(inheritance)) if inheritance

        parse s(:begin, *body.compact), :statement
      ensure
        self.ivars = ivars
        @class_name = class_name
        @class_parent = class_parent
        @namespace.defineProps @rbstack.pop
        @namespace.leave unless @ast.type == :class_module
      end
    end

    # handle properties, methods, and constructors
    # @block_this and @block_depth are used by self
    # @instance_method is used by super and self
    handle :prop, :method, :constructor do |*args|
      begin
        instance_method, @instance_method = @instance_method, @ast
        @block_this, @block_depth = false, 0
        if @ast.type == :prop
          obj, props = *args
          if props.length == 1
            prop, descriptor = props.flatten
            parse s(:send, s(:const, nil, :Object), :defineProperty,
              obj, s(:sym, prop), s(:hash,
                *descriptor.map { |key, value| s(:pair, s(:sym, key), value) }))
          else
            parse s(:send, s(:const, nil, :Object), :defineProperties,
              obj, s(:hash, *props.map {|hprop, hdescriptor|
                s(:pair, s(:sym, hprop), 
                  s(:hash, *hdescriptor.map {|key, value| 
                    s(:pair, s(:sym, key), value) }))}))
          end
        elsif @ast.type == :method
          parse s(:send, *args)
        elsif args.first.children.first
          parse s(:send, args.first.children.first,
            "#{args.first.children[1]}=", s(:block, s(:send, nil, :proc), 
              *args[1..-1]))
        else
          parse s(:def, args.first.children[1], *args[1..-1])
        end
      ensure
        @instance_method = instance_method
        @block_this, @block_depth = nil, nil
      end
    end
  end
end
