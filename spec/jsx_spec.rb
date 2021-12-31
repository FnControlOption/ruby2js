gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/jsx'
require 'ruby2js/filter/jsx'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/react'

# this spec handles two very different, JSX related transformations:
#
# * ruby/JSX to ruby/wunderbar, which is used by both filter/react and
#   filter/vue to produce an intermediate "pure ruby" version of
#   ruby intermixed with (X)HTML element syntax, which is subsequently
#   converted to JS.
#
# * ruby/wunderbar to JSX, which is implemented by filter/JSX to enable
#   a one way syntax conversion of wunderbar style calls to JSX syntax.


describe Ruby2JS::Filter::JSX do
  
  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2015, 
      filters: [Ruby2JS::Filter::JSX, Ruby2JS::Filter::Functions]).to_s)
  end

  def to_rb(string)
    _(Ruby2JS.jsx2_rb(string))
  end
  
  describe "ruby/JSX to ruby/wunderbar" do
    describe "tags" do
      it "should handle self enclosed elements" do
        to_rb( '<br/>' ).must_equal '_br'
      end

      it "should handle attributes and text" do
        to_rb( '<a href=".">text</a>' ).must_equal(
          ['_a(href: ".") do', '_("text")', 'end'].join("\n"))
      end

      it "should handle attributes expressions" do
        to_rb( '<img src={link}/>' ).must_equal('_img(src: link)')
      end

      it "should handle nested valuess" do
        to_rb( '<div><br/></div>' ).must_equal(
          ['_div do', '_br', 'end'].join("\n"))
      end

      it "should handle fragments" do
        to_rb( '<><h1/><h2/></>' ).must_equal(
          ['_ do', '_h1', '_h2', 'end'].join("\n"))
      end
    end

    describe "text and strings" do
      it "should handle backslashes in attribute values" do
        # backslashes are not escape characters in HTML context
        to_rb( '<a b="\\"/>' ).must_equal('_a(b: "\\\\")')
        to_rb( "<a b='\\'/>" ).must_equal("_a(b: '\\\\')")
      end

      it "should handle backslashes in text" do
        to_rb( 'a\\b' ).must_equal('_("a\\\\b")')
      end

      it "should handle mixed text" do
        to_rb( 'before <p> line 1 <br/> line 2 </p> after' ).must_equal(
          ['_("before")', '_p do', '_("line 1")', '_br',
            '_("line 2")', 'end', '_("after")'].join("\n"))
      end
    end

    describe "values" do
      it "should handle expressions in text" do
        to_rb( 'hello {name}!' ).must_equal(
          ['_("hello ")', '_(name)', '_("!")'].join("\n"))
      end
      
      it "should handle strings in attribute values" do
        # backslashes are not escape characters in HTML context
        to_rb( '<a b={"{\\"}"}/>' ).must_equal('_a(b: "{\"}")')
        to_rb( "<a b={'{\\'}'}/>" ).must_equal("_a(b: '{\\'}')")
      end
      
      it "should handle interpolated strings" do
        to_rb( '<a b={"d#{"e"}f"}/>' ).must_equal('_a(b: "d#{"e"}f")')
      end
      
      it "should handle elements in expressions" do
        to_rb( '{a && <a/>}' ).must_equal('a && _a')
        to_rb( '{a && <a href="."/>}' ).must_equal('a && _a(href: ".")')
        to_rb( '{a>b ? <a/> : <b/>}' ).must_equal('a>b ? _a : _b')
        to_rb( '{list.map {|item| <li>{item}</li>}}' ).
          must_equal('list.map {|item| _li do;_(item);end}')
      end
    end

    describe "errors" do
      it "should detect invalid element name" do
        _(assert_raises {to_rb '<<'}.message).
          must_equal 'invalid character in element name: "<"'
      end

      it "should detect invalid character after element close" do
        _(assert_raises {to_rb '</->'}.message).
          must_equal 'invalid character in element: "-"'
      end

      it "should detect invalid character after void element close" do
        _(assert_raises {to_rb '<a/a>'}.message).
          must_equal 'invalid character in element: "/"'
      end

      it "should detect an unclosed element" do
        _(assert_raises {to_rb '<a>'}.message).
          must_equal 'missing close tag for: "a"'
        _(assert_raises {to_rb '<a></b>'}.message).
          must_equal 'missing close tag for: "a"'
      end

      it "should detect a stray close element" do
        _(assert_raises {to_rb '</a>'}.message).
          must_equal 'close tag for element that is not open: a'
      end

      it "should detect invalid attribute name" do
        _(assert_raises {to_rb '<a b/>'}.message).
          must_equal 'invalid character in attribute name: "/"'
      end

      it "should detect missing attribute value" do
        _(assert_raises {to_rb '<a b>'}.message).
          must_equal 'missing "=" after attribute "b" in element "a"'
      end

      it "should detect missing attribute value quotes" do
        _(assert_raises {to_rb '<a b=1>'}.message).
          must_equal 'invalid value for attribute "b" in element "a"'
      end

      it "should detect unclosed element" do
        _(assert_raises {to_rb '<a'}.message).
          must_equal 'unclosed element "a"'
        _(assert_raises {to_rb '<a b'}.message).
          must_equal 'unclosed element "a"'
        _(assert_raises {to_rb '<a b='}.message).
          must_equal 'unclosed element "a"'
      end

      it "should detect unclosed string" do
        _(assert_raises {to_rb '<a b="'}.message).
          must_equal 'unclosed quote'
        _(assert_raises {to_rb "<a b='"}.message).
          must_equal 'unclosed quote'
      end

      it "should detect unclosed value" do
        _(assert_raises {to_rb '<a b={x'}.message).
          must_equal 'unclosed value'
        _(assert_raises {to_rb '{x'}.message).
          must_equal 'unclosed value'
      end

      it "should detect unclosed value string" do
        _(assert_raises {to_rb '<a b={"'}.message).
          must_equal 'unclosed quote'
        _(assert_raises {to_rb '<a b={"\\'}.message).
          must_equal 'unclosed quote'
        _(assert_raises {to_rb "<a b={'"}.message).
          must_equal 'unclosed quote'
        _(assert_raises {to_rb "<a b={'\\'"}.message).
          must_equal 'unclosed quote'
      end
    end
  end

  describe "React.createElement to JSX" do
    it "should handle element, attrs, text" do
      to_js( 'React.createElement("hr")' ).
        must_equal '<hr/>'
      to_js( 'React.createElement("br", nil)' ).
        must_equal '<br/>'
      to_js( 'React.createElement("img", {src: "x.jpg"})' ).
        must_equal '<img src="x.jpg"/>'
      to_js( 'React.createElement("a", {href: "."}, "text")' ).
        must_equal '<a href=".">text</a>'
    end

    it "should handle nesting" do
      to_js( 'React.createElement("p", nil, "text", React.createElement("br", nil), data)' ).
        must_equal '<p>text<br/>{data}</p>'
    end

    it "should NOT handle non-constant element names" do
      to_js( 'React.createElement(x)' ).
        must_equal( 'React.createElement(x)' )
    end
  end

  describe "ruby/wunderbar to JSX" do
    it "should handle self enclosed values" do
      to_js( '_br' ).must_equal '<br/>'
    end

    it "should handle attributes and text" do
      to_js( '_a "text", href: "."' ).must_equal '<a href=".">text</a>'
    end

    it "should handle nested valuess" do
      to_js( '_div do _br; end' ).must_equal '<div><br/></div>'
    end

    it "should handle implicit iteration" do
      to_js( '_tr(rows) {|row| _td row}' ).
        must_equal '<tr>{rows.map(row => <td>{row}</td>)}</tr>'
    end

    it "should handle markaby style classes and id" do
      to_js( '_a.b.c.d!' ).must_equal '<a id="d" className="b c"/>'
    end

    it "should handle fragments" do
      to_js( '_ {_h1; _h2}' ).must_equal '<><h1/><h2/></>'
      to_js( '_(key: "x"){_h1; _h2}' ).
        must_equal '<React.Fragment key="x"><h1/><h2/></React.Fragment>'
    end

    it "should handle enclosing markaby style classes and id" do
      to_js( '_a.b.c.d! do _e; end' ).
       must_equal '<a id="d" className="b c"><e/></a>'
    end

    it "should class for to className" do
      to_js( '_div class: "foo"' ).
       must_equal '<div className="foo"/>'
    end

    it "should map for to htmlFor" do
      to_js( '_label "foo", for: "foo"' ).
       must_equal '<label htmlFor="foo">foo</label>'
    end
  end

  describe 'control structures' do
    it "should handle if" do
      to_js('_p {"hi" if a}').
        must_equal '<p>{a ? "hi" : null}</p>'
    end

    it "should handle each" do
      to_js('_ul { a.each {|b| _li b} }').
        must_equal '<ul>{a.map(b => <li>{b}</li>)}</ul>'
    end

    it "should handle blocks" do
      to_js('_div {if a; _br; _br; end}').
        must_equal '<div>{a ? <><br/><br/></> : null}</div>'
    end
  end

  describe :logging do
    it "should map wunderbar logging calls to console" do
      to_js( 'Wunderbar.debug "a"' ).must_equal 'console.debug("a")'
      to_js( 'Wunderbar.info "a"' ).must_equal 'console.info("a")'
      to_js( 'Wunderbar.warn "a"' ).must_equal 'console.warn("a")'
      to_js( 'Wunderbar.error "a"' ).must_equal 'console.error("a")'
      to_js( 'Wunderbar.fatal "a"' ).must_equal 'console.error("a")'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include JSX" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::JSX
    end
  end
end
