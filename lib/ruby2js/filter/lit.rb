require 'ruby2js'

module Ruby2JS
  module Filter
    module Lit
      include SEXP
      extend  SEXP

      LITELEMENT_IMPORT = s(:import,
        [s(:pair, s(:sym, :from), s(:str, "lit"))],
        [s(:const, nil, :LitElement), s(:attr, nil, :css), s(:attr, nil, :html)]) 

      def initialize(node)
        super
        @le_props = nil
      end

      def on_ivar(node)
        return super unless @le_props&.include?(node.children.first)
        process s(:attr, s(:self), node.children.first.to_s[1..-1])
      end

      def on_ivasgn(node)
        return super unless @le_props&.include?(node.children.first)
        return super unless node.children.length > 1

        process s(:send, s(:self), node.children.first.to_s[1..-1] + '=',
          process(node.children[1]))
      end

      def on_op_asgn(node)
        return super unless node.children.first.type == :ivasgn
        var = node.children.first.children.first
        return super unless @le_props&.include?(var)
        super node.updated(nil, [s(:attr, s(:attr, nil, :this),
          var.to_s[1..-1]), *node.children[1..-1]])
      end

      def on_class(node)
        class_name, inheritance, *body = node.children
        return super unless inheritance == s(:const, nil, :LitElement)

        @le_props = {}
        le_walk(node)

        prepend_list << LITELEMENT_IMPORT if modules_enabled?

        nodes = body.dup
        if nodes.length == 1 and nodes.first&.type == :begin
          nodes = nodes.first.children.dup
        end

        # insert/update static get properties() {}
        unless @le_props.empty?
          values = nodes.find_index {|child| 
            (child.type == :defs and child.children[0..1] == [s(:self), :properties]) or
            (child.type == :send and child.children[0..1] == [s(:self), :properties=])
          }

          if values == nil
            if es2022
              nodes.unshift process(s(:casgn, nil, :properties, 
                s(:hash, *@le_props.map {|name, type| s(:pair, s(:sym, name.to_s[1..-1]), 
                  s(:hash, s(:pair, s(:sym, :type), s(:const, nil, type || :String))))})))
            else
              nodes.unshift process(s(:defp, s(:self), :properties, s(:args), s(:return, 
                s(:hash, *@le_props.map {|name, type| s(:pair, s(:sym, name.to_s[1..-1]), 
                  s(:hash, s(:pair, s(:sym, :type), s(:const, nil, type || :String))))}))))
            end
          elsif nodes[values].children.last.type == :hash
            le_props = @le_props.map {|name, type| 
              [s(:sym, name.to_s[1..-1].to_sym), 
                s(:hash, s(:pair, s(:sym, :type), s(:const, nil, type || :String)))]
            }.to_h.merge(
              nodes[values].children.last.children.map {|pair| pair.children}.to_h
            )

            nodes[values] = nodes[values].updated(nil,
              [*nodes[values].children[0..-2], s(:hash,
                *le_props.map {|name, value| s(:pair, name, value)})])
          end
        end

        # customElement is converted to customElements.define
        customElement = nodes.find_index {|child| 
          child&.type == :send and (child.children[0..1] == [nil, :customElement] || child.children[0..1] == [nil, :custom_element])
        }
        if customElement and nodes[customElement].children.length == 3
          nodes[customElement] = nodes[customElement].updated(nil,
            [s(:attr, nil, :customElements), :define,
              nodes[customElement].children.last, class_name])
        end

        # render of a string is converted to a taglit :html
        render = nodes.find_index {|child| 
          child&.type == :def and child.children.first == :render
        }
        if render and %i[str dstr begin if block].include?(nodes[render].children[2]&.type)
          nodes[render] = nodes[render].updated(:deff,
            [*nodes[render].children[0..1],
              s(:autoreturn, html_wrap(nodes[render].children[2]))])
        end

        # self.styles returning string is converted to a taglit :css
        styles = nodes.find_index {|child| 
          (child&.type == :ivasgn and child.children[0] == :@styles) or
          (child&.type == :defs and child.children[0..1] == [s(:self), :styles]) or
          (child&.type == :send and child.children[0..1] == [s(:self), :styles=])
        }
        if styles and %i[str dstr].include?(nodes[styles].children.last&.type)
          string = nodes[styles].children.last
          string = s(:dstr, string) if string.type == :str
          children = string.children.dup

          while children.length > 1 and children.last.type == :str and
            children.last.children.last.strip == ''
            children.pop
          end

          if children.last.type == :str
            children << s(:str, children.pop.children.first.chomp)
          end

          if es2022
            nodes[styles] = nodes[styles].updated(:casgn,
              [nil, :styles, s(:taglit, s(:sym, :css),
                s(:dstr, *children))])
          else
            nodes[styles] = nodes[styles].updated(:defp,
              [s(:self), :styles, s(:args),
                s(:autoreturn, s(:taglit, s(:sym, :css),
                  s(:dstr, *children)))])
          end
        end

        # insert super calls into initializer
        initialize = nodes.find_index {|child| 
          child&.type == :def and child.children.first == :initialize
        }
        if initialize and nodes[initialize].children.length == 3
          statements = nodes[initialize].children[2..-1]

          if statements.length == 1 and statements.first.type == :begin
            statements = statements.first.children 
          end

          unless statements.any? {|statement| %i[super zuper].include? statement.type}
            nodes[initialize] = nodes[initialize].updated(nil,
              [*nodes[initialize].children[0..1],
                s(:begin, s(:zsuper), *statements)])
          end
        end

        # props/methods inherited from LitElement
        props = {
          hasUpdated: s(:self),
          performUpdate: s(:autobind, s(:self)),
          renderRoot: s(:self),
          requestUpdate: s(:autobind, s(:self)),
          shadowRoot: s(:self),
          updateComplete: s(:self),
        }

        # local props
        props.merge! @le_props.keys.map {|prop| [prop.to_sym, s(:self)]}.to_h

        nodes.unshift s(:defineProps, props)

        nodes.pop unless nodes.last

        node.updated(nil, [*node.children[0..1], s(:begin, *process_all(nodes))])
      ensure
        @le_props = nil
      end

      def html_wrap(node)
        return node unless node.is_a?(Parser::AST::Node)

        if node.type == :str and node.children.first.strip.start_with? '<'
          s(:taglit, s(:sym, :html), s(:dstr, node))
        elsif node.type == :dstr
          prefix = ''
          node.children.each do |child|
            break unless child.type == :str
            prefix += child.children.first
          end

          return node unless prefix.strip.start_with? '<'

          children = node.children.map do |child|
            if child.type == :str
              child
            else
              html_wrap(child)
            end
          end

          while children.length > 1 and children.last.type == :str and
            children.last.children.last.strip == ''
            children.pop
          end

          if children.last.type == :str
            children << s(:str, children.pop.children.first.chomp)
          end

          s(:taglit, s(:sym, :html), node.updated(nil, children))
        elsif node.type == :begin
          node.updated(nil, node.children.map {|child| html_wrap(child)})
        elsif node.type == :if
          node.updated(nil, [node.children.first,
            *node.children[1..2].map {|child| html_wrap(child)}])
        elsif node.type == :block and
          node.children.first.children[1] == :map
          node.updated(nil, [*node.children[0..1],
            html_wrap(node.children[2])])
        else
          node
        end
      end

      def on_def(node)
        node = super
        return node if [:constructor, :initialize].include?(node.children.first)

        children = node.children[1..-1]

        node.updated nil, [node.children[0], children.first,
          *(children[1..-1].map {|child| html_wrap(child) })]
      end

      # analyze ivar usage
      def le_walk(node)
        node.children.each do |child|
          next unless child.is_a? Parser::AST::Node

          if child.type == :ivar
            next if child.children.first.to_s.start_with?("@_")

            @le_props[child.children.first] ||= nil
          elsif child.type == :ivasgn || child.type == :op_asgn
            prop = child.children.first
            unless prop.is_a? Symbol
              prop = prop.children.first if prop.type == :ivasgn
              next unless prop.is_a? Symbol
            end

            next if prop.to_s.start_with?("@_")

            @le_props[prop] = case child.children.last.type
            when :str, :dstr
              :String
            when :array
              :Array
            when :int, :float
              :Number
            when :true, :false
              :Boolean
            else
              @le_props[prop] || :Object
            end
          else
            le_walk(child)
          end
        end
      end

      def on_send(node)
        target, method, *args = node.children

        return super if target
        return super unless %i{query queryAll queryAsync}.include? method
        return super unless args.length == 1

        result = s(:csend, s(:attr, s(:self), :renderRoot),
          (method == :query ? 'querySelector' : 'querySelectorAll'),
          args.first)

        if method == :queryAsync
          result = s(:block, s(:send, s(:attr, s(:self), :updateComplete),
            :then), s(:args), result)
        end

        result
      end
    end

    DEFAULTS.push Lit
  end
end
