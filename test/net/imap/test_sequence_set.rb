# frozen_string_literal: true

require "net/imap"
require "test/unit"

class IMAPSequenceSetTest < Test::Unit::TestCase
  # alias for convenience
  SequenceSet     = Net::IMAP::SequenceSet
  DataFormatError = Net::IMAP::DataFormatError

  test "compared to reference Set, add many random values" do
    set    = Set.new
    seqset = SequenceSet.new
    10.times do
      nums = Array.new(2000) { rand(1..10_000) }
      set.merge nums
      seqset.merge nums
      assert_equal set, seqset.to_set
      assert seqset.elements.size <= set.size
    end
    assert seqset.elements.size < set.size
  end

  test "compared to reference Set, add many large ranges" do
    set    = Set.new
    seqset = SequenceSet.new
    (1..10000).each_slice(250) do
      set.merge _1
      seqset.merge(*_1)
      assert_equal set, seqset.to_set
      assert_equal 1, seqset.elements.size
    end
  end

  test "#== equality by value (not by identity or representation)" do
    assert_equal SequenceSet.new, SequenceSet.new
    assert_equal SequenceSet.new("1"), SequenceSet[1]
    assert_equal SequenceSet.new("*"), SequenceSet[:*]
    assert_equal SequenceSet["2:4"], SequenceSet["4:2"]
  end

  test "#freeze" do
    set = SequenceSet.new "2:4,7:11,99,999"
    assert !set.frozen?
    set.freeze
    assert set.frozen?
    assert Ractor.shareable?(set) if defined?(Ractor)
  end

  %i[clone dup].each do |method|
    test "##{method}" do
      orig = SequenceSet.new "2:4,7:11,99,999"
      copy = orig.send method
      assert_equal orig, copy
      orig << 123
      copy << 456
      assert_not_equal orig, copy
      assert  orig.include?(123)
      assert  copy.include?(456)
      assert !copy.include?(123)
      assert !orig.include?(456)
    end
  end

  if defined?(Ractor)
    test "#freeze makes ractor sharable (deeply frozen)" do
      assert Ractor.shareable? SequenceSet.new("1:9,99,999").freeze
    end

    test ".[] returns ractor sharable (deeply frozen)" do
      assert Ractor.shareable? SequenceSet["2:8,88,888"]
    end

    test "#clone preserves ractor sharability (deeply frozen)" do
      assert Ractor.shareable? SequenceSet["3:7,77,777"].clone
    end
  end

  test ".new, input must be valid" do
    assert_raise DataFormatError do SequenceSet.new ""           end
    assert_raise DataFormatError do SequenceSet.new []           end
    assert_raise DataFormatError do SequenceSet.new [0]          end
    assert_raise DataFormatError do SequenceSet.new "0"          end
    assert_raise DataFormatError do SequenceSet.new [2**33]      end
    assert_raise DataFormatError do SequenceSet.new (2**33).to_s end
    assert_raise DataFormatError do SequenceSet.new "0:2"        end
    assert_raise DataFormatError do SequenceSet.new ":2"         end
    assert_raise DataFormatError do SequenceSet.new " 2"         end
    assert_raise DataFormatError do SequenceSet.new "2 "         end
    assert_raise DataFormatError do SequenceSet.new Time.now     end
  end

  test ".[] must not be empty" do
    assert_raise DataFormatError do SequenceSet[] end
    assert_raise DataFormatError do SequenceSet[nil] end
  end

  test "#limit" do
    set = SequenceSet["1:100,500"]
    assert_equal [1..99],                  set.limit(max: 99).ranges
    assert_equal (1..15).to_a,             set.limit(max: 15).numbers
    assert_equal SequenceSet["1:100"], set.limit(max: 101)
    assert_equal SequenceSet["1:97"],  set.limit(max: 97)
    assert_equal [1..99],                  set.limit(max: 99).ranges
    assert_equal (1..15).to_a,             set.limit(max: 15).numbers
  end

  test "#limit with *" do
    assert_equal SequenceSet.new("2,4,5,6,7,9,12,13,14,15"),
                 SequenceSet.new("2,4:7,9,12:*").limit(max: 15)
    assert_equal(SequenceSet["37"],
                 SequenceSet["50,60,99:*"].limit(max: 37))
    assert_equal(SequenceSet["1:100,300"],
                 SequenceSet["1:100,500:*"].limit(max: 300))
    assert_equal [15], SequenceSet["3967:*"].limit(max: 15).numbers
    assert_equal [15], SequenceSet["*:12293456"].limit(max: 15).numbers
  end

  test "#limit with empty result" do
    assert_equal nil, SequenceSet["1234567890"].limit(max: 37)
    assert_equal nil, SequenceSet["99:195,458"].limit(max: 37)
  end

  test "values for '*'" do
    assert_equal "*",   SequenceSet[?*].to_s
    assert_equal "*",   SequenceSet[:*].to_s
    assert_equal "*",   SequenceSet[-1].to_s
    assert_equal "*",   SequenceSet[2**32].to_s
    assert_equal "*",   SequenceSet[[?*]].to_s
    assert_equal "*",   SequenceSet[[:*]].to_s
    assert_equal "*",   SequenceSet[[-1]].to_s
    assert_equal "*",   SequenceSet[[2**32]].to_s
    assert_equal "1:*", SequenceSet[1..].to_s
    assert_equal "1:*", SequenceSet[1..-1].to_s
    assert_equal "1:*", SequenceSet[1..2**32].to_s
  end

  def test_empty
    refute SequenceSet.new("1:*").empty?
    refute SequenceSet.new(:*).empty?
    assert SequenceSet.new(nil).empty?
  end

  def test_full
    assert SequenceSet.new("1:*").full?
    refute SequenceSet.new(1..2**32-1).full?
    refute SequenceSet.new(nil).full?
  end

  def test_to_sequence_set
    assert_equal (set = SequenceSet["*"]),              set.to_sequence_set
    assert_equal (set = SequenceSet["15:36,5,99,*,2"]), set.to_sequence_set
  end

  def test_plus
    seqset = -> { SequenceSet.new _1 }
    assert_equal seqset["1,5"],       seqset["1"]         + seqset["5"]
    assert_equal seqset["1,*"],       seqset["*"]         + seqset["1"]
    assert_equal seqset["1:*"],       seqset["1:4"]       + seqset["5:*"]
    assert_equal seqset["1:*"],       seqset["5:*"]       + seqset["1:4"]
    assert_equal seqset["1:5"],       seqset["1,3,5"]     + seqset["2,4"]
    assert_equal seqset["1:3,5,7:9"], seqset["1,3,5,7:8"] + seqset["2,8:9"]
    assert_equal seqset["1:*"],       seqset["1,3,5,7:*"] + seqset["2,4:6"]
  end

  def test_add
    seqset = -> { SequenceSet.new _1 }
    assert_equal seqset["1,5"],       seqset["1"].add("5")
    assert_equal seqset["1,*"],       seqset["*"].add(1)
    assert_equal seqset["1:*"],       seqset["1:4"].add(5..)
    assert_equal seqset["1:3,5,7:9"], seqset["1,3,5,7:8"].add(seqset["2,8:9"])
    assert_equal seqset["1:*"],       seqset["5:*"]   << (1..4)
    assert_equal seqset["1:5"],       seqset["1,3,5"] << seqset["2,4"]
  end

  def test_minus
    seqset = -> { SequenceSet.new _1 }
    assert_equal seqset["1,5"],       seqset["1,5"] - 9
    assert_equal seqset["1,5"],       seqset["1,5"] - "3"
    assert_equal seqset["1,5"],       seqset["1,3,5"] - [3]
    assert_equal seqset["1,9"],       seqset["1,3:9"] - "2:8"
    assert_equal seqset["1,9"],       seqset["1:7,9"] - (2..8)
    assert_equal seqset["1,9"],       seqset["1:9"] - (2..8).to_a
    assert_equal seqset["1,5"],       seqset["1,5:9,11:99"] - "6:999"
    assert_equal seqset["1,5,99"],    seqset["1,5:9,11:88,99"] - ["6:98"]
    assert_equal seqset["1,5,99"],    seqset["1,5:6,8:9,11:99"] - "6:98"
    assert_equal seqset["1,5,11:99"], seqset["1,5:6,8:9,11:99"] - "6:9"
    assert_equal seqset["1:10"],      seqset["1:*"] - (11..)
    assert_equal seqset[nil],         seqset["1,5"] - [1..8, 10..]
  end

  def test_intersection
    seqset = -> { SequenceSet.new _1 }
    assert_equal seqset[nil],         seqset["1,5"] & "9"
    assert_equal seqset["1,5"],       seqset["1:5"].intersection([1, 5..9])
    assert_equal seqset["1,5"],       seqset["1:5"] & [1, 5, 9, 55]
    assert_equal seqset["*"],         seqset["9999:*"] & "1,5,9,*"
  end

  def test_subtract
    seqset = -> { SequenceSet.new _1 }
    assert_equal seqset["1,5"],       seqset["1,5"].subtract("9")
    assert_equal seqset["1,5"],       seqset["1,5"].subtract("3")
    assert_equal seqset["1,5"],       seqset["1,3,5"].subtract("3")
    assert_equal seqset["1,9"],       seqset["1,3:9"].subtract("2:8")
    assert_equal seqset["1,9"],       seqset["1:7,9"].subtract("2:8")
    assert_equal seqset["1,9"],       seqset["1:9"].subtract("2:8")
    assert_equal seqset["1,5"],       seqset["1,5:9,11:99"].subtract("6:999")
    assert_equal seqset["1,5,99"],    seqset["1,5:9,11:88,99"].subtract("6:98")
    assert_equal seqset["1,5,99"],    seqset["1,5:6,8:9,11:99"].subtract("6:98")
    assert_equal seqset["1,5,11:99"], seqset["1,5:6,8:9,11:99"].subtract("6:9")
  end

  def test_min
    assert_equal 3, SequenceSet.new("34:3").min
    assert_equal 345, SequenceSet.new("345,678").min
    assert_nil SequenceSet.new.min
  end

  def test_max
    assert_equal  34, SequenceSet["34:3"].max
    assert_equal 678, SequenceSet["345,678"].max
    assert_equal 678, SequenceSet["345:678"].max(star: "unused")
    assert_equal  :*, SequenceSet["345:*"].max
    assert_equal nil, SequenceSet["345:*"].max(star: nil)
    assert_equal "*", SequenceSet["345:*"].max(star: "*")
    assert_nil SequenceSet.new.max(star: "ignored")
  end

  def test_minmax
    assert_equal [  3,   3], SequenceSet["3"].minmax
    assert_equal [ :*,  :*], SequenceSet["*"].minmax
    assert_equal [ 99,  99], SequenceSet["*"].minmax(star: 99)
    assert_equal [  3,  34], SequenceSet["34:3"].minmax
    assert_equal [345, 678], SequenceSet["345,678"].minmax
    assert_equal [345, 678], SequenceSet["345:678"].minmax(star: "unused")
    assert_equal [345,  :*], SequenceSet["345:*"].minmax
    assert_equal [345, nil], SequenceSet["345:*"].minmax(star: nil)
    assert_equal [345, "*"], SequenceSet["345:*"].minmax(star: "*")
    assert_nil SequenceSet.new.minmax(star: "ignored")
  end

  def test_add?
    assert_equal(SequenceSet.new("1:3,5,7:9"),
                 SequenceSet.new("1,3,5,7:8").add?("2,8:9"))
    assert_nil   SequenceSet.new("1,3,5,7:*").add?("3,9:91")
  end

  def test_include
    assert SequenceSet["2:4"].include?(3)
    assert SequenceSet["2,4:7,9,12:*"] === 2
    assert SequenceSet["2,4:7,9,12:*"].cover?(2222)
    set = SequenceSet.new Array.new(1_000) { rand(1..1500) }
    set.numbers
      .each do assert set.include?(_1) end
    (~set).limit(max: 1_501).numbers
      .each do assert !set.include?(_1) end
  end

  def test_complement_empty
    assert_equal SequenceSet.new("1:*"), SequenceSet.new.complement!
    assert_equal SequenceSet.new, SequenceSet.new("1:*").complement!
  end

  data(
    # desc         => [expected, input, freeze]
    "empty"        => ["#<Net::IMAP::SequenceSet empty>",   nil],
    "normalized"   => ['#<Net::IMAP::SequenceSet "1:2">',   [2, 1]],
    "denormalized" => ['#<Net::IMAP::SequenceSet "2,1">',   "2,1"],
    "star"         => ['#<Net::IMAP::SequenceSet "*">',     "*"],
    "frozen"       => ['Net::IMAP::SequenceSet["1,3,5:*"]', [1, 3, 5..], true],
  )
  def test_inspect((expected, input, freeze))
    seqset = freeze ? SequenceSet[input] : SequenceSet.new(input)
    assert_equal expected, seqset.inspect
  end

  data "single number", {
    input:      "123456",
    elements:   [123_456],
    ranges:     [123_456..123_456],
    numbers:    [123_456],
    to_s:       "123456",
    normalize:  "123456",
    count:      1,
    complement: "1:123455,123457:*",
  }, keep: true

  data "single range", {
    input:      "1:3",
    elements:   [1..3],
    ranges:     [1..3],
    numbers:    [1, 2, 3],
    to_s:       "1:3",
    normalize:  "1:3",
    count:      3,
    complement: "4:*",
  }, keep: true

  data "simple numbers list", {
    input:      "1,3,5",
    elements:   [   1,    3,    5],
    ranges:     [1..1, 3..3, 5..5],
    numbers:    [   1,    3,    5],
    to_s:       "1,3,5",
    normalize:  "1,3,5",
    count:      3,
    complement: "2,4,6:*",
  }, keep: true

  data "numbers and ranges list", {
    input:      "1:3,5,7:9,46",
    elements:   [1..3,    5, 7..9,     46],
    ranges:     [1..3, 5..5, 7..9, 46..46],
    numbers:    [1, 2, 3, 5, 7, 8, 9,  46],
    to_s:       "1:3,5,7:9,46",
    normalize:  "1:3,5,7:9,46",
    count:      8,
    complement: "4,6,10:45,47:*",
  }, keep: true

  data "just *", {
    input:      "*",
    elements:   [:*],
    ranges:     [:*..],
    numbers:    [:*],
    to_s:       "*",
    normalize:  "*",
    count:      1,
    complement: "1:%d" % [2**32-1]
  }, keep: true

  # need to use a very large number, or else the numbers array will be enormous.
  #
  #   (2**32-1) - 4_294_967_000 < 1_000 => true
  data "range with *", {
    input:      "4294967000:*",
    elements:   [4_294_967_000..],
    ranges:     [4_294_967_000..],
    numbers:    RangeError,
    to_s:       "4294967000:*",
    normalize:  "4294967000:*",
    count:      2**32 - 4_294_967_000,
    complement: "1:4294966999",
  }, keep: true

  data "* sorts last", {
    input:      "5,*,7",
    elements:   [5, 7, :*],
    ranges:     [5..5, 7..7, :*..],
    numbers:    [5, 7, :*],
    to_s:       "5,*,7",
    normalize:  "5,7,*",
    complement: "1:4,6,8:%d" % [2**32-1],
    count:      3,
  }, keep: true

  data "out of order", {
    input:      "46,7:6,15,3:1",
    elements:   [1..3, 6..7, 15, 46],
    ranges:     [1..3, 6..7, 15..15, 46..46],
    numbers:    [1, 2, 3, 6, 7, 15, 46],
    to_s:       "46,7:6,15,3:1",
    normalize:  "1:3,6:7,15,46",
    count:      7,
    complement: "4:5,8:14,16:45,47:*",
  }, keep: true

  data "adjacent", {
    input:      "1,2,3,5,7:9,10:11",
    elements:   [1..3, 5,    7..11],
    ranges:     [1..3, 5..5, 7..11],
    numbers:    [1, 2, 3, 5, 7, 8, 9, 10, 11],
    to_s:       "1,2,3,5,7:9,10:11",
    normalize:  "1:3,5,7:11",
    count:      9,
    complement: "4,6,12:*",
  }, keep: true

  data "overlapping", {
    input:      "1:5,3:7,10:9,10:11",
    elements:   [1..7, 9..11],
    ranges:     [1..7, 9..11],
    numbers:    [1, 2, 3, 4, 5, 6, 7,  9, 10, 11],
    to_s:       "1:5,3:7,10:9,10:11",
    normalize:  "1:7,9:11",
    count:      10,
    complement: "8,12:*",
  }, keep: true

  data "contained", {
    input:      "1:5,3:4,9:11,10",
    elements:   [1..5, 9..11],
    ranges:     [1..5, 9..11],
    numbers:    [1, 2, 3, 4, 5, 9, 10, 11],
    to_s:       "1:5,3:4,9:11,10",
    normalize:  "1:5,9:11",
    count:      8,
    complement: "6:8,12:*",
  }, keep: true

  data "empty", {
    input:      nil,
    elements:   [],
    ranges:     [],
    numbers:    [],
    to_s:       "",
    normalize:  "",
    count:      0,
    complement: "1:*",
  }, keep: true

  def test_elements(data)
    assert_equal data[:elements], SequenceSet.new(data[:input]).elements
  end

  def test_ranges(data)
    assert_equal data[:ranges], SequenceSet.new(data[:input]).ranges
  end

  def test_to_s(data)
    assert_equal data[:to_s], SequenceSet.new(data[:input]).to_s
  end

  def test_count(data)
    assert_equal data[:count], SequenceSet.new(data[:input]).count
  end

  %i[atom astring].each do |method|
    define_method :"test_#{method}" do |data|
      if (expected = data[:to_s]).empty?
        assert_raise DataFormatError do
          SequenceSet.new(data[:input]).send(method)
        end
      else
        assert_equal data[:to_s], SequenceSet.new(data[:input]).send(method)
      end
    end
  end

  def test_complement(data)
    assert_equal(data[:complement],
                 SequenceSet.new(data[:input]).complement.to_s)
  end

  def test_numbers(data)
    expected = data[:numbers]
    if expected.is_a?(Class) && expected < Exception
      assert_raise expected do SequenceSet.new(data[:input]).numbers end
    else
      assert_equal expected, SequenceSet.new(data[:input]).numbers
    end
  end

  def test_brackets(data)
    if (input = data[:input])
      seqset = SequenceSet[input]
      assert_equal data[:normalize], seqset.to_s
      assert seqset.frozen?
    else
      assert_raise DataFormatError do SequenceSet[input] end
    end
  end

  def test_normalized(data)
    assert_equal data[:normalize], SequenceSet.new(data[:input]).normalize.to_s
  end

  def test_complement_2x(data)
    set = SequenceSet.new(data[:input])
    assert_equal set, set.complement.complement
  end

  def test_add_complemented(data)
    set = SequenceSet.new(data[:input])
    assert_equal SequenceSet.new("1:*"), set + set.complement
  end

end
