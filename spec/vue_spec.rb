gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/vue'

describe Ruby2JS::Filter::Vue do
  
  def to_js(string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Vue], scope: self).to_s
  end
  
  describe :createClass do
    it "should create classes" do
      to_js( 'class FooBar<Vue; end' ).
        must_include 'var FooBar = Vue.component("foo-bar",'
    end

    it "should convert initialize methods to data" do
      to_js( 'class Foo<Vue; def initialize(); end; end' ).
        must_include ', {data: function() {return {}}'
    end

    it "should convert insert initialize methods if none present" do
      to_js( 'class Foo<Vue; def render; _h1 @title; end; end' ).
        must_include ', {data: function() {return {title: undefined}}'
    end

    it "should convert merge uninitialized values - simple" do
      to_js( 'class Foo<Vue; def initialize; @var = ""; end; ' +
        'def render; _h1 @title; end; end' ).
        must_include ', {data: function() {return {var: "", title: undefined}}'
    end

    it "should convert merge uninitialized values - complex" do
      to_js( 'class Foo<Vue; def initialize; value = "x"; @var = value; end; ' +
        'def render; _h1 @title; end; end' ).
        must_include ', {data: function() {' +
          'var $_ = {title: undefined}; var value = "x"; $_.var = value; ' +
          'return $_}'
    end

    it "should initialize, accumulate, and return state if complex" do
      to_js( 'class Foo<Vue; def initialize; @a=1; b=2; @b = b; end; end' ).
        must_include 'data: function() {var $_ = {}; $_.a = 1; ' +
          'var b = 2; $_.b = b; return $_}'
    end

    it "should initialize, accumulate, and return state if ivars are read" do
      to_js( 'class Foo<Vue; def initialize; @a=1; @b = @a; end; end' ).
        must_include ', {data: function() {var $_ = {}; $_.a = 1; ' +
          '$_.b = $_.a; return $_}}'
    end

    it "should initialize, accumulate, and return state if multi-assignment" do
      to_js( 'class Foo<Vue; def initialize; @a=@b=1; end; end' ).
        must_include ', {data: function() {var $_ = {b: undefined}; ' +
          '$_.a = $_.b = 1; return $_}}'
    end

    it "should initialize, accumulate, and return state if op-assignment" do
      to_js( 'class Foo<Vue; def initialize; @a||=1; end; end' ).
        must_include ', {data: function() {var $_ = {a: undefined}; ' +
          '$_.a = $_.a || 1; return $_}}'
    end

    it "should collapse instance variable assignments into a return" do
      to_js( 'class Foo<Vue; def initialize; @a=1; @b=2; end; end' ).
        must_include 'data: function() {return {a: 1, b: 2}}'
    end

    it "should handle lifecycle methods" do
      to_js( 'class Foo<Vue; def updated; console.log "."; end; end' ).
        must_include ', updated: function() {return console.log(".")}'
    end

    it "should handle other methods" do
      to_js( 'class Foo<Vue; def clicked; @counter+=1; end; end' ).
        must_include ', methods: {clicked: function() {this.$data.counter++}}'
    end
  end

  describe "Wunderbar/JSX processing" do
    # https://github.com/vuejs/babel-plugin-transform-vue-jsx#difference-from-react-jsx
    it "should create components" do
      to_js( 'class Foo<Vue; def render; _A; end; end' ).
        must_include '$h(A)'
    end

    it "should create components with properties" do
      to_js( 'class Foo<Vue; def render; _A title: "foo"; end; end' ).
        must_include '$h(A, {props: {title: "foo"}})'
    end

    it "should create elements with event listeners" do
      to_js( 'class Foo<Vue; def render; _A onAlert: self.alert; end; end' ).
        must_include '$h(A, {on: {alert: this.alert}})'
    end

    it "should create elements for HTML tags" do
      to_js( 'class Foo<Vue; def render; _a; end; end' ).
        must_include '$h("a")'
    end

    it "should create elements with attributes and text" do
      to_js( 'class Foo<Vue; def render; _a "name", href: "link"; end; end' ).
        must_include '$h("a", {attrs: {href: "link"}}, "name")'
    end

    it "should create elements with DOM Propoerties" do
      to_js( 'class Foo<Vue; def render; _a domPropsTextContent: "name"; end; end' ).
        must_include '$h("a", {domProps: {textContent: "name"}})'
    end

    it "should create elements with event listeners" do
      to_js( 'class Foo<Vue; def render; _a onClick: self.click; end; end' ).
        must_include '$h("a", {on: {click: this.click}})'
    end

    it "should create elements with native event listeners" do
      to_js( 'class Foo<Vue; def render; _a nativeOnClick: self.click; end; end' ).
        must_include '$h("a", {nativeOn: {click: this.click}})'
    end

    it "should create elements with class hash expressions" do
      to_js( 'class Foo<Vue; def render; _a class: {foo: true}; end; end' ).
        must_include '$h("a", {class: {foo: true}})'
    end

    it "should create elements with class array expressions" do
      to_js( 'class Foo<Vue; def render; _a class: ["foo", "bar"]; end; end' ).
        must_include '$h("a", {class: ["foo", "bar"]})'
    end

    it "should create elements with style expressions" do
      to_js( 'class Foo<Vue; def render; _a style: {color: "red"}; end; end' ).
        must_include '$h("a", {style: {color: "red"}})'
    end

    it "should create elements with a key value" do
      to_js( 'class Foo<Vue; def render; _a key: "key"; end; end' ).
        must_include '$h("a", {key: "key"})'
    end

    it "should create elements with a ref value" do
      to_js( 'class Foo<Vue; def render; _a ref: "ref"; end; end' ).
        must_include '$h("a", {ref: "ref"})'
    end

    it "should create elements with a refInFor value" do
      to_js( 'class Foo<Vue; def render; _a refInFor: true; end; end' ).
        must_include '$h("a", {refInFor: true})'
    end

    it "should create elements with a slot value" do
      to_js( 'class Foo<Vue; def render; _a slot: "slot"; end; end' ).
        must_include '$h("a", {slot: "slot"})'
    end

    it "should create simple nested elements" do
      to_js( 'class Foo<Vue; def render; _a {_b}; end; end' ).
        must_include ', render: function($h) {return $h("a", [$h("b")])}'
    end

    it "should handle options with blocks" do
      to_js( 'class Foo<Vue; def render; _a options do _b; end; end; end' ).
        must_include ', render: function($h) ' +
          '{return $h("a", options, [$h("b")])}'
    end

    it "should create complex nested elements" do
      result = to_js('class Foo<Vue; def render; _a {c="c"; _b c}; end; end')

      result.must_include 'return $h("a", function() {'
      result.must_include 'var $_ = []; var c = "c"; $_.push($h("b", c));'
      result.must_include 'return $_}())'
    end

    it "should treat explicit calls to Vue.createElement as simple" do
      to_js( 'class Foo<Vue; def render; _a {Vue.createElement("b")}; ' +
        'end; end' ).
        must_include '$h("a", [$h("b")])'
    end

    it "should push results of explicit calls to Vue.createElement" do
      result = to_js('class Foo<Vue; def render; _a {c="c"; ' +
        'Vue.createElement("b", c)}; end; end')

      result.must_include '$h("a", function() {'
      result.must_include 'var $_ = [];'
      result.must_include '$_.push($h("b", c));'
      result.must_include 'return $_'
      result.must_include '}())'
    end

    it "should handle call with blocks to Vue.createElement" do
      result = to_js( 'class Foo<Vue; def render; ' +
        'Vue.createElement("a") {_b}; end; end' )
      result.must_include '$h("a", function() {'
      result.must_include 'var $_ = [];'
      result.must_include '$_.push($h("b"));'
      result.must_include 'return $_'
      result.must_include '}())'
    end

    it "should iterate" do
      result = to_js('class Foo<Vue; def render; _ul list ' + 
        'do |i| _li i; end; end; end')

      result.must_include '$h("ul", function() {'
      result.must_include 'var $_ = [];'
      result.must_include 'list.forEach(function(i) {'
      result.must_include '{$_.push($h("li", i))}'
      result.must_include 'return $_'
      result.must_include '}())'
    end

    it "should iterate with markaby style classes/ids" do
      result = to_js('class Foo<Vue; def render; _ul.todos list ' + 
        'do |i| _li i; end; end; end')

      result.must_include '$h("ul", {class: ["todos"]}, function() {'
      result.must_include 'var $_ = [];'
      result.must_include 'list.forEach(function(i) {'
      result.must_include '{$_.push($h("li", i))}'
      result.must_include 'return $_'
      result.must_include '}())'
    end

    it "should handle text nodes" do
      to_js( 'class Foo<Vue; def render; _a {_ @text}; end; end' ).
        must_include '[this._v(this.$data.text)]'
    end

    it "should apply text nodes" do
      to_js( 'class Foo<Vue; def render; _a {text="hi"; _ text}; end; end' ).
        must_include 'var text = "hi"; $_.push(self._v(text));'
    end

    it "should handle arbitrary nodes" do
      to_js( 'class Foo<Vue; def render; _a {_[@text]}; end; end' ).
        must_include 'return $h("a", [this.$data.text])'
    end

    it "should handle lists of arbitrary nodes" do
      to_js( 'class Foo<Vue; def render; _a {_[@text, @text]}; end; end' ).
        must_include '$h("a", [this.$data.text, this.$data.text])'
    end

    it "should apply arbitrary nodes" do
      to_js( 'class Foo<Vue; def render; _a {text="hi"; _[text]}; end; end' ).
        must_include 'var text = "hi"; $_.push(text);'
    end

    it "should apply list of arbitrary nodes" do
      to_js( 'class Foo<Vue; def render; _a {text="hi"; _[text, text]}; end; end' ).
        must_include 'var text = "hi"; $_.push(text, text);'
    end
  end

  describe "class attributes" do
    it "should handle class attributes" do
      to_js( 'class Foo<Vue; def render; _a class: "b"; end; end' ).
        must_include '$h("a", {class: ["b"]})'
    end

    it "should handle className attributes" do
      to_js( 'class Foo<Vue; def render; _a className: "b"; end; end' ).
        must_include '$h("a", {class: ["b"]})'
    end

    it "should handle class attributes with spaces" do
      to_js( 'class Foo<Vue; def render; _a class: "b c"; end; end' ).
        must_include '$h("a", {class: ["b", "c"]})'
    end

    it "should handle markaby syntax" do
      to_js( 'class Foo<Vue; def render; _a.b.c href: "d"; end; end' ).
        must_include '$h("a", {class: ["b", "c"], attrs: {href: "d"}})'
    end

    it "should handle mixed strings" do
      to_js( 'class Foo<Vue; def render; _a.b class: "c"; end; end' ).
        must_include '$h("a", {class: ["b", "c"]})'
    end

    it "should handle mixed strings and a value" do
      to_js( 'class Foo<Vue; def render; _a.b class: c; end; end' ).
        must_include '$h("a", {attrs: {class: "b " + (c || "")}})'
    end

    it "should create elements with markup and a class hash expression" do
      to_js( 'class Foo<Vue; def render; _a.bar class: {foo: true}; end; end' ).
        must_include '$h("a", {class: {foo: true, bar: true}})'
    end

    it "should create elements with markup and a class array expression" do
      to_js( 'class Foo<Vue; def render; _a.bar class: ["foo"]; end; end' ).
        must_include '$h("a", {class: ["foo", "bar"]})'
    end

    it "should handle mixed strings and a conditional value" do
      to_js( 'class Foo<Vue; def render; _a.b class: ("c" if d); end; end' ).
        must_include '$h("a", {attrs: {class: "b " + (d ? "c" : "")}})'
    end

    it "should handle only a value" do
      to_js( 'class Foo<Vue; def render; _a class: c; end; end' ).
        must_include '$h("a", {attrs: {class: c}})'
    end
  end

  describe "other attributes" do
    it "should handle markaby syntax ids" do
      to_js( 'class Foo<Vue; def render; _a.b! href: "c"; end; end' ).
        must_include '$h("a", {attrs: {id: "b", href: "c"}})'
    end

    it "should map style string attributes to hashes" do
      to_js( 'class Foo<Vue; def render; _a ' +
        'style: "color: blue; margin-top: 0"; end; end' ).
        must_include '{style: {color: "blue", marginTop: 0}}'
    end
  end

  describe "map gvars/ivars/cvars to refs/state/prop" do
    it "should map instance variables to state" do
      to_js( 'class Foo<Vue; def method; @x; end; end' ).
        must_include 'this.$data.x'
    end

    it "should map setting instance variables to setting properties" do
      to_js( 'class Foo<Vue; def method; @x=1; end; end' ).
        must_include 'this.$data.x = 1'
    end

    it "should handle parallel instance variables assignment" do
      to_js( 'class Foo<Vue; def method(); @x=@y=1; end; end' ).
        must_include 'this.$data.x = this.$data.y = 1'
    end

    it "should enumerate properties" do
      to_js( 'class Foo<Vue; def render; _span @@x + @@y; end; end' ).
        must_include '{props: ["x", "y"]'
    end

    it "should map class variables to properties" do
      to_js( 'class Foo<Vue; def method; @@x; end; end' ).
        must_include 'this.$props.x'
    end

    it "should not support assigning to class variables" do
      proc { 
        to_js( 'class Foo<Vue; def method; @@x=1; end; end' )
      }.must_raise NotImplementedError
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include vue" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::Vue
    end
  end
end
