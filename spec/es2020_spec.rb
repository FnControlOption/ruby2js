gem 'minitest'
require 'minitest/autorun'

describe "ES2020 support" do
  
  def to_js( string)
    _(Ruby2JS.convert(string, eslevel: 2020, filters: []).to_s)
  end

  def to_js_fn(string)
    _(Ruby2JS.convert(string, eslevel: 2020,
      filters: [Ruby2JS::Filter::Functions]).to_s)
  end

  def to_js_nullish( string)
    _(Ruby2JS.convert(string, eslevel: 2020, or: :nullish, filters: []).to_s)
  end

  describe :matchAll do
    it 'should handle scan' do
      to_js_fn( 'str.scan(/\d/)' ).must_equal 'str.match(/\d/g)'
      to_js_fn( 'str.scan(/(\d)(\d)/)' ).
        must_equal 'Array.from(str.matchAll(/(\\d)(\\d)/g), s => s.slice(1))'
      to_js_fn( 'str.scan(pattern)' ).
        must_equal 'Array.from(str.matchAll(new RegExp(pattern, "g")), ' +
          's => s.slice(1))'
    end
  end

  describe :regex do
    it "should handle regular expression indexes" do
      to_js_fn( 'a[/\d+/]' ).must_equal 'a.match(/\d+/)?.[0]'
      to_js_fn( 'a[/(\d+)/, 1]' ).must_equal 'a.match(/(\d+)/)?.[1]'
    end
  end

  describe "nullish coalescing operator" do
    it "should map || operator based on :or option" do
      to_js( 'a || b' ).must_equal 'a || b'
      to_js_nullish( 'a || b' ).must_equal 'a ?? b'
    end
  end

  describe :OptionalChaining do
    unless (RUBY_VERSION.split('.').map(&:to_i) <=> [2, 3, 0]) == -1
      it "should support conditional attribute references" do
        to_js('x=a&.b').must_equal 'let x = a?.b'
      end

      it "should chain conditional attribute references" do
        to_js('x=a&.b&.c').must_equal 'let x = a?.b?.c'
      end

      it "should support conditional indexing" do
        to_js('x=a&.[](b)').must_equal 'let x = a?.[b]'
      end
    end

    it "should combine conditions when it can" do
      to_js('x=a && a.b').must_equal 'let x = a?.b'
    end

    it "should ignore unrelated ands" do
      to_js('x=x && a && a.b && a.b.c && a.b.c.d && y').
        must_equal 'let x = x && a?.b?.c?.d && y'
    end
  end
end
