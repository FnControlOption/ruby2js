require 'ruby2js'

module Ruby2JS
  module Filter
    module TaggedTemplates
      include SEXP

      def initialize(*args)
        super
      end

      def on_send(node)
        target, method, *args = node.children
        return super unless target.nil? and es2015

        tagged_methods = @options[:template_literal_tags] || [:html, :css]

        if tagged_methods.include?(method) && args.length == 1
          strnode = process args.first
          if strnode.type == :str
            # convert regular strings to literal strings
            strnode = strnode.updated(:dstr, [s(:str, strnode.children.first.chomp("\n"))])
          elsif strnode.type == :dstr
            # for literal strings, chomp a newline off the end
            if strnode.children.last.type == :str && strnode.children.last.children[0].end_with?("\n")
             children = [*strnode.children.take(strnode.children.length - 1), s(:str, strnode.children.last.children[0].chomp)]
             strnode = s(:dstr, *children)
            end
          else
            return super
          end

          S(:taglit, s(:sym, method), strnode)
        else
          super
        end
      end
    end

    DEFAULTS.push TaggedTemplates
  end
end
