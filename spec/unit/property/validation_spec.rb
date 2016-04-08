require "support/shared/integration/integration_helper"

describe "Chef::Resource.property validation" do
  include IntegrationSupport

  module Namer
    @i = 0
    def self.next_resource_name
      "chef_resource_property_spec_#{@i += 1}"
    end

    def self.reset_index
      @current_index = 0
    end

    def self.current_index
      @current_index
    end

    def self.next_index
      @current_index += 1
    end
  end

  def lazy(&block)
    Chef::DelayedEvaluator.new(&block)
  end

  before do
    Namer.reset_index
  end

  def self.new_resource_name
    Namer.next_resource_name
  end

  let(:resource_class) do
    new_resource_name = self.class.new_resource_name
    Class.new(Chef::Resource) do
      resource_name new_resource_name
      def blah
        Namer.next_index
      end

      def self.blah
        "class#{Namer.next_index}"
      end
    end
  end

  let(:resource) do
    resource_class.new("blah")
  end

  def self.english_join(values)
    return "<nothing>" if values.size == 0
    return values[0].inspect if values.size == 1
    "#{values[0..-2].map { |v| v.inspect }.join(", ")} and #{values[-1].inspect}"
  end

  def self.with_property(*properties, &block)
    tags_index = properties.find_index { |p| !p.is_a?(String) }
    if tags_index
      properties, tags = properties[0..tags_index - 1], properties[tags_index..-1]
    else
      tags = []
    end
    properties = properties.map { |property| "property #{property}" }
    context "With properties #{english_join(properties)}", *tags do
      before do
        properties.each do |property_str|
          resource_class.class_eval(property_str, __FILE__, __LINE__)
        end
      end
      instance_eval(&block)
    end
  end

  def self.validation_test(validation, success_values, failure_values, *tags)
    with_property ":x, #{validation}", *tags do
      it "gets nil when retrieving the initial (non-set) value" do
        expect(resource.x).to be_nil
      end
      success_values.each do |v|
        it "value #{v.inspect} is valid" do
          resource.instance_eval { @x = "default" }
          expect(resource.x v).to eq v
          expect(resource.x).to eq v
        end
      end
      failure_values.each do |v|
        it "value #{v.inspect} is invalid" do
          expect { resource.x v }.to raise_error Chef::Exceptions::ValidationFailed
          resource.instance_eval { @x = "default" }
          expect { resource.x v }.to raise_error Chef::Exceptions::ValidationFailed
        end
      end
      it "setting x to nil when it is already nil does not emit a warning" do
        expect(resource.x nil).to be_nil
        expect(resource.x).to be_nil
      end
      it "changing x to nil warns that the get will change to a set in Chef 13 and does not change the value" do
        resource.instance_eval { @x = "default" }
        expect { resource.x nil }.to raise_error Chef::Exceptions::DeprecatedFeatureError,
          /An attempt was made to change x from "default" to nil by calling x\(nil\). In Chef 12, this does a get rather than a set. In Chef 13, this will change to set the value to nil./
        Chef::Config[:treat_deprecation_warnings_as_errors] = false
        expect(resource.x nil).to eq "default"
        expect(resource.x).to eq "default"
      end
    end
    if tags.include?(:nil_is_valid)
      with_property ":x, #{validation}, default: nil" do
        it "setting x to nil when it is already nil does not emit a warning" do
          expect(resource.x nil).to be_nil
          expect(resource.x).to be_nil
        end
        it "changing x to nil warns that the get will change to a set in Chef 13 and does not change the value" do
          resource.instance_eval { @x = "default" }
          expect { resource.x nil }.to raise_error Chef::Exceptions::DeprecatedFeatureError,
            /An attempt was made to change x from "default" to nil by calling x\(nil\). In Chef 12, this does a get rather than a set. In Chef 13, this will change to set the value to nil./
          Chef::Config[:treat_deprecation_warnings_as_errors] = false
          expect(resource.x nil).to eq "default"
          expect(resource.x).to eq "default"
        end
      end
    else
      it "property :x, #{validation}, default: nil warns that the default is invalid" do
        expect { resource_class.class_eval("property :x, #{validation}, default: nil", __FILE__, __LINE__) }.to raise_error Chef::Exceptions::DeprecatedFeatureError,
          /Default value nil is invalid for property x of resource chef_resource_property_spec_(\d+). Possible fixes: 1. Remove 'default: nil' if nil means 'undefined'. 2. Set a valid default value if there is a reasonable one. 3. Allow nil as a valid value of your property \(for example, 'property :x, \[ String, nil \], default: nil'\)./
      end
      context "With property :x, #{validation}, default: nil" do
        before do
          Chef::Config[:treat_deprecation_warnings_as_errors] = false
          resource_class.class_eval("property :x, #{validation}, default: nil", __FILE__, __LINE__)
          Chef::Config[:treat_deprecation_warnings_as_errors] = true
        end

        it "changing x to nil emits a warning that the value is invalid and does not change the value" do
          resource.instance_eval { @x = "default" }
          expect { resource.x nil }.to raise_error Chef::Exceptions::DeprecatedFeatureError,
            /nil is an invalid value for x of resource chef_resource_property_spec_(\d+). In Chef 13, this warning will change to an error./
          Chef::Config[:treat_deprecation_warnings_as_errors] = false
          expect(resource.x nil).to eq "default"
          expect(resource.x).to eq "default"
        end
      end
    end
  end

  context "basic get, set, and nil set" do
    with_property ":x, kind_of: String" do
      context "when the variable already has a value" do
        before do
          resource.instance_eval { @x = "default" }
        end
        it "get succeeds" do
          expect(resource.x).to eq "default"
        end
        it "set to valid value succeeds" do
          expect(resource.x "str").to eq "str"
          expect(resource.x).to eq "str"
        end
        it "set to invalid value raises ValidationFailed" do
          expect { resource.x 10 }.to raise_error Chef::Exceptions::ValidationFailed
        end
        it "set to nil emits a deprecation warning and does a get" do
          expect { resource.x nil }.to raise_error Chef::Exceptions::DeprecatedFeatureError
          Chef::Config[:treat_deprecation_warnings_as_errors] = false
          resource.x "str"
          expect(resource.x nil).to eq "str"
          expect(resource.x).to eq "str"
        end
      end
      context "when the variable does not have an initial value" do
        it "get succeeds" do
          expect(resource.x).to be_nil
        end
        it "set to valid value succeeds" do
          expect(resource.x "str").to eq "str"
          expect(resource.x).to eq "str"
        end
        it "set to invalid value raises ValidationFailed" do
          expect { resource.x 10 }.to raise_error Chef::Exceptions::ValidationFailed
        end
        it "set to nil emits no warning because the value would not change" do
          expect(resource.x nil).to be_nil
        end
      end
    end
    with_property ":x, [ String, nil ]" do
      context "when the variable already has a value" do
        before do
          resource.instance_eval { @x = "default" }
        end
        it "get succeeds" do
          expect(resource.x).to eq "default"
        end
        it "set(nil) emits a warning that the value will be set, but does not set the value" do
          expect { resource.x nil }.to raise_error Chef::Exceptions::DeprecatedFeatureError,
            /An attempt was made to change x from "default" to nil by calling x\(nil\). In Chef 12, this does a get rather than a set. In Chef 13, this will change to set the value to nil./
          Chef::Config[:treat_deprecation_warnings_as_errors] = false
          expect(resource.x nil).to eq "default"
          expect(resource.x).to eq "default"
        end
        it "set to valid value succeeds" do
          expect(resource.x "str").to eq "str"
          expect(resource.x).to eq "str"
        end
        it "set to invalid value raises ValidationFailed" do
          expect { resource.x 10 }.to raise_error Chef::Exceptions::ValidationFailed
        end
      end
      context "when the variable does not have an initial value" do
        it "get succeeds" do
          expect(resource.x).to be_nil
        end
        it "set(nil) sets the value" do
          expect(resource.x nil).to be_nil
          expect(resource.x).to be_nil
        end
        it "set to valid value succeeds" do
          expect(resource.x "str").to eq "str"
          expect(resource.x).to eq "str"
        end
        it "set to invalid value raises ValidationFailed" do
          expect { resource.x 10 }.to raise_error Chef::Exceptions::ValidationFailed
        end
      end
    end
  end

  # Bare types
  context "bare types" do
    validation_test "String",
      [ "hi" ],
      [ 10 ]

    validation_test ":a",
      [ :a ],
      [ :b ]

    validation_test ":a, is: :b",
      [ :a, :b ],
      [ :c ]

    validation_test ":a, is: [ :b, :c ]",
      [ :a, :b, :c ],
      [ :d ]

    validation_test "[ :a, :b ], is: :c",
      [ :a, :b, :c ],
      [ :d ]

    validation_test "[ :a, :b ], is: [ :c, :d ]",
      [ :a, :b, :c, :d ],
      [ :e ]

    validation_test "nil",
      [ ],
      [ :a ],
      :nil_is_valid

    validation_test "[ nil ]",
      [ ],
      [ :a ],
      :nil_is_valid

    validation_test "[]",
      [],
      [ :a ]
  end

  # is
  context "is" do
    # Class
    validation_test "is: String",
      [ "a", "" ],
      [ :a, 1 ]

    # Value
    validation_test "is: :a",
      [ :a ],
      [ :b ]

    validation_test "is: [ :a, :b ]",
      [ :a, :b ],
      [ [ :a, :b ] ]

    validation_test "is: [ [ :a, :b ] ]",
      [ [ :a, :b ] ],
      [ :a, :b ]

    # Regex
    validation_test "is: /abc/",
      %w{abc wowabcwow},
      [ "", "abac" ]

    # Property
    validation_test "is: Chef::Property.new(is: :a)",
      [ :a ],
      [ :b ]

    # RSpec Matcher
    class Globalses
      extend RSpec::Matchers
    end

    validation_test "is: Globalses.eq(10)",
      [ 10 ],
      [ 1 ]

    # Proc
    validation_test "is: proc { |x| x }",
      [ true, 1 ],
      [ false ]

    validation_test "is: proc { |x| x > blah }",
      [ 10 ],
      [ -1 ]

    validation_test "is: nil",
      [ ],
      [ "a" ],
      :nil_is_valid

    validation_test "is: [ String, nil ]",
      [ "a" ],
      [ :b ],
      :nil_is_valid

    validation_test "is: []",
      [],
      [ :a ]
  end

  # Combination
  context "combination" do
    validation_test 'kind_of: String, equal_to: "a"',
      [ "a" ],
      [ "b" ],
      :nil_is_valid
  end

  # equal_to
  context "equal_to" do
    # Value
    validation_test "equal_to: :a",
      [ :a ],
      [ :b ],
      :nil_is_valid

    validation_test "equal_to: [ :a, :b ]",
      [ :a, :b ],
      [ [ :a, :b ] ],
      :nil_is_valid

    validation_test "equal_to: [ [ :a, :b ] ]",
      [ [ :a, :b ] ],
      [ :a, :b ],
      :nil_is_valid

    validation_test "equal_to: nil",
      [ ],
      [ "a" ],
      :nil_is_valid

    validation_test 'equal_to: [ "a", nil ]',
      [ "a" ],
      [ "b" ],
      :nil_is_valid

    validation_test 'equal_to: [ nil, "a" ]',
      [ "a" ],
      [ "b" ],
      :nil_is_valid

    validation_test "equal_to: []",
      [],
      [ :a ],
      :nil_is_valid

  end

  # kind_of
  context "kind_of" do
    validation_test "kind_of: String",
      [ "a" ],
      [ :b ],
      :nil_is_valid

    validation_test "kind_of: [ String, Symbol ]",
      [ "a", :b ],
      [ 1 ],
      :nil_is_valid

    validation_test "kind_of: [ Symbol, String ]",
      [ "a", :b ],
      [ 1 ],
      :nil_is_valid

    validation_test "kind_of: NilClass",
      [ ],
      [ "a" ],
      :nil_is_valid

    validation_test "kind_of: [ NilClass, String ]",
      [ "a" ],
      [ :a ],
      :nil_is_valid

    validation_test "kind_of: []",
      [],
      [ :a ],
      :nil_is_valid

    validation_test "kind_of: nil",
      [],
      [ :a ],
      :nil_is_valid
  end

  # regex
  context "regex" do
    validation_test "regex: /abc/",
      [ "xabcy" ],
      [ "gbh", 123 ],
      :nil_is_valid

    validation_test "regex: [ /abc/, /z/ ]",
      %w{xabcy aza},
      [ "gbh", 123 ],
      :nil_is_valid

    validation_test "regex: [ /z/, /abc/ ]",
      %w{xabcy aza},
      [ "gbh", 123 ],
      :nil_is_valid

    validation_test "regex: [ [ /z/, /abc/ ], [ /n/ ] ]",
      %w{xabcy aza ana},
      [ "gbh", 123 ],
      :nil_is_valid

    validation_test "regex: []",
      [],
      [ :a ],
      :nil_is_valid

    validation_test "regex: nil",
      [],
      [ :a ],
      :nil_is_valid
  end

  # callbacks
  context "callbacks" do
    validation_test 'callbacks: { "a" => proc { |x| x > 10 }, "b" => proc { |x| x%2 == 0 } }',
      [ 12 ],
      [ 11, 4 ],
      :nil_is_valid

    validation_test 'callbacks: { "a" => proc { |x| x%2 == 0 }, "b" => proc { |x| x > 10 } }',
      [ 12 ],
      [ 11, 4 ],
      :nil_is_valid

    validation_test 'callbacks: { "a" => proc { |x| x.nil? } }',
      [ ],
      [ "a" ],
      :nil_is_valid

    validation_test "callbacks: {}",
      [ :a ],
      [],
      :nil_is_valid
  end

  # respond_to
  context "respond_to" do
    validation_test "respond_to: :split",
      [ "hi" ],
      [ 1 ],
      :nil_is_valid

    validation_test 'respond_to: "split"',
      [ "hi" ],
      [ 1 ],
      :nil_is_valid

    validation_test "respond_to: :to_s",
      [ :a ],
      [],
      :nil_is_valid

    validation_test "respond_to: [ :split, :to_s ]",
      [ "hi" ],
      [ 1 ],
      :nil_is_valid

    validation_test "respond_to: %w(split to_s)",
      [ "hi" ],
      [ 1 ],
      :nil_is_valid

    validation_test "respond_to: [ :to_s, :split ]",
      [ "hi" ],
      [ 1 ],
      :nil_is_valid

    validation_test "respond_to: []",
      [ :a ],
      [],
      :nil_is_valid

    validation_test "respond_to: nil",
      [ :a ],
      [],
      :nil_is_valid
  end

  context "cannot_be" do
    validation_test "cannot_be: :empty",
      [ 1, [1, 2], { a: 10 } ],
      [ [] ],
      :nil_is_valid

    validation_test 'cannot_be: "empty"',
      [ 1, [1, 2], { a: 10 } ],
      [ [] ],
      :nil_is_valid

    validation_test "cannot_be: [ :empty, :nil ]",
      [ 1, [1, 2], { a: 10 } ],
      [ [] ],
      :nil_is_valid

    validation_test 'cannot_be: [ "empty", "nil" ]',
      [ 1, [1, 2], { a: 10 } ],
      [ [] ],
      :nil_is_valid

    validation_test "cannot_be: [ :nil, :empty ]",
      [ 1, [1, 2], { a: 10 } ],
      [ [] ],
      :nil_is_valid

    validation_test "cannot_be: [ :empty, :nil, :blahblah ]",
      [ 1, [1, 2], { a: 10 } ],
      [ [] ],
      :nil_is_valid

    validation_test "cannot_be: []",
      [ :a ],
      [],
      :nil_is_valid

    validation_test "cannot_be: nil",
      [ :a ],
      [],
      :nil_is_valid

  end

  context "required" do
    with_property ":x, required: true" do
      it "if x is not specified, retrieval fails" do
        expect { resource.x }.to raise_error Chef::Exceptions::ValidationFailed
      end
      it "value 1 is valid" do
        expect(resource.x 1).to eq 1
        expect(resource.x).to eq 1
      end
      it "value nil emits a validation failed error because it must have a value" do
        expect { resource.x nil }.to raise_error Chef::Exceptions::ValidationFailed
      end
      context "and value is set to something other than nil" do
        before { resource.x 10 }
        it "value nil emits a deprecation warning and does a get" do
          expect { resource.x nil }.to raise_error Chef::Exceptions::DeprecatedFeatureError
          Chef::Config[:treat_deprecation_warnings_as_errors] = false
          resource.x 1
          expect(resource.x nil).to eq 1
          expect(resource.x).to eq 1
        end
      end
    end

    with_property ":x, [String, nil], required: true" do
      it "if x is not specified, retrieval fails" do
        expect { resource.x }.to raise_error Chef::Exceptions::ValidationFailed
      end
      it "value nil is not valid (required means 'not nil')" do
        expect { resource.x nil }.to raise_error Chef::Exceptions::ValidationFailed
      end
      it "value '1' is valid" do
        expect(resource.x "1").to eq "1"
        expect(resource.x).to eq "1"
      end
      it "value 1 is invalid" do
        expect { resource.x 1 }.to raise_error Chef::Exceptions::ValidationFailed
      end
    end

    with_property ":x, name_property: true, required: true" do
      it "if x is not specified, the name property is returned" do
        expect(resource.x).to eq "blah"
      end
      it "value 1 is valid" do
        expect(resource.x 1).to eq 1
        expect(resource.x).to eq 1
      end
      it "value nil emits a deprecation warning and does a get" do
        expect { resource.x nil }.to raise_error Chef::Exceptions::DeprecatedFeatureError
        Chef::Config[:treat_deprecation_warnings_as_errors] = false
        resource.x 1
        expect(resource.x nil).to eq 1
        expect(resource.x).to eq 1
      end
    end

    with_property ":x, default: 10, required: true" do
      it "if x is not specified, the default is returned" do
        expect(resource.x).to eq 10
      end
      it "value 1 is valid" do
        expect(resource.x 1).to eq 1
        expect(resource.x).to eq 1
      end
      it "value nil is invalid" do
        expect { resource.x nil }.to raise_error Chef::Exceptions::DeprecatedFeatureError
        Chef::Config[:treat_deprecation_warnings_as_errors] = false
        resource.x 1
        expect(resource.x nil).to eq 1
        expect(resource.x).to eq 1
      end
    end
  end

  context "custom validators (def _pv_blarghle)" do
    before do
      Chef::Config[:treat_deprecation_warnings_as_errors] = false
    end

    with_property ":x, blarghle: 1" do
      context "and a class that implements _pv_blarghle" do
        before do
          resource_class.class_eval do
            def _pv_blarghle(opts, key, value)
              if _pv_opts_lookup(opts, key) != value
                raise Chef::Exceptions::ValidationFailed, "ouch"
              end
            end
          end
        end

        it "value 1 is valid" do
          expect(resource.x 1).to eq 1
          expect(resource.x).to eq 1
        end

        it "value '1' is invalid" do
          Chef::Config[:treat_deprecation_warnings_as_errors] = false
          expect { resource.x "1" }.to raise_error Chef::Exceptions::ValidationFailed
        end

        it "value nil does a get" do
          Chef::Config[:treat_deprecation_warnings_as_errors] = false
          resource.x 1
          resource.x nil
          expect(resource.x).to eq 1
        end
      end
    end

    with_property ":x, blarghle: 1" do
      context "and a class that implements _pv_blarghle" do
        before do
          resource_class.class_eval do
            def _pv_blarghle(opts, key, value)
              if _pv_opts_lookup(opts, key) != value
                raise Chef::Exceptions::ValidationFailed, "ouch"
              end
            end
          end
        end

        it "value 1 is valid" do
          expect(resource.x 1).to eq 1
          expect(resource.x).to eq 1
        end

        it "value '1' is invalid" do
          expect { resource.x "1" }.to raise_error Chef::Exceptions::ValidationFailed
        end

        it "value nil does a get" do
          resource.x 1
          resource.x nil
          expect(resource.x).to eq 1
        end
      end
    end
  end
end
