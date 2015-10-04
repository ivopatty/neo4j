require 'neo4j/version'

# require "delegate"
# require "time"
# require "set"
#
# require "active_support/core_ext"
# require "active_support/json"
# require "active_support/inflector"
# require "active_support/time_with_zone"

require 'neo4j-core'
require 'neo4j/core/query'
require 'active_model'
require 'active_support/concern'
require 'active_support/core_ext/class/attribute.rb'

require 'active_attr'
require 'neo4j/errors'
require 'neo4j/config'
require 'neo4j/wrapper'
require 'neo4j/active_rel/rel_wrapper'
require 'neo4j/active_node/node_wrapper'
require 'neo4j/shared/type_converters'
require 'neo4j/shared/rel_type_converters'
require 'neo4j/type_converters'
require 'neo4j/paginated'

require 'neo4j/timestamps'

require 'neo4j/shared/callbacks'
require 'neo4j/shared/declared_property'
require 'neo4j/shared/declared_property_manager'
require 'neo4j/shared/property'
require 'neo4j/shared/persistence'
require 'neo4j/shared/validations'
require 'neo4j/shared/identity'
require 'neo4j/shared/serialized_properties'
require 'neo4j/shared/typecaster'
require 'neo4j/shared/initialize'
require 'neo4j/shared'

require 'neo4j/active_rel/callbacks'
require 'neo4j/active_rel/initialize'
require 'neo4j/active_rel/property'
require 'neo4j/active_rel/persistence'
require 'neo4j/active_rel/validations'
require 'neo4j/active_rel/query'
require 'neo4j/active_rel/related_node'
require 'neo4j/active_rel/types'
require 'neo4j/active_rel'

require 'neo4j/active_node/dependent'
require 'neo4j/active_node/dependent/query_proxy_methods'
require 'neo4j/active_node/dependent/association_methods'
require 'neo4j/active_node/query_methods'
require 'neo4j/active_node/query/query_proxy_unpersisted'
require 'neo4j/active_node/query/query_proxy_methods'
require 'neo4j/active_node/query/query_proxy_enumerable'
require 'neo4j/active_node/query/query_proxy_find_in_batches'
require 'neo4j/active_node/query/query_proxy_eager_loading'
require 'neo4j/active_node/query/query_proxy_link'
require 'neo4j/active_node/labels/reloading'
require 'neo4j/active_node/labels'
require 'neo4j/active_node/id_property/accessor'
require 'neo4j/active_node/id_property'
require 'neo4j/active_node/callbacks'
require 'neo4j/active_node/initialize'
require 'neo4j/active_node/property'
require 'neo4j/active_node/persistence'
require 'neo4j/active_node/validations'
require 'neo4j/active_node/rels'
require 'neo4j/active_node/reflection'
require 'neo4j/active_node/unpersisted'
require 'neo4j/active_node/has_n'
require 'neo4j/active_node/has_n/association_cypher_methods'
require 'neo4j/active_node/has_n/association'
require 'neo4j/active_node/query/query_proxy'
require 'neo4j/active_node/query'
require 'neo4j/active_node/scope'
require 'neo4j/active_node'

require 'neo4j/active_node/orm_adapter'
if defined?(Rails)
  require 'rails/generators'
  require 'rails/generators/neo4j_generator'
end

require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/core_ext/array/conversions'
require 'active_support/core_ext/hash/conversions'
require 'active_support/core_ext/hash/slice'
require 'active_support/core_ext/time/acts_like'

module ActiveModel
  module Serializers
    # == Active Model XML Serializer
    module Xml
      extend ActiveSupport::Concern
      include ActiveModel::Serialization

      included do
        extend ActiveModel::Naming
      end

      class Serializer #:nodoc:
        class Attribute #:nodoc:
          attr_reader :name, :value, :type

          def initialize(name, serializable, value)
            @name, @serializable = name, serializable

            if value.acts_like?(:time) && value.respond_to?(:in_time_zone)
              value  = value.in_time_zone
            end

            @value = value
            @type  = compute_type
          end

          def decorations
            decorations = {}
            decorations[:encoding] = 'base64' if type == :binary
            decorations[:type] = (type == :string) ? nil : type
            decorations[:nil] = true if value.nil?
            decorations
          end

          protected

          def compute_type
            return if value.nil?
            type = ActiveSupport::XmlMini::TYPE_NAMES[value.class.name]
            type ||= :string if value.respond_to?(:to_str)
            type ||= :yaml
            type
          end
        end

        class MethodAttribute < Attribute #:nodoc:
        end

        attr_reader :options

        def initialize(serializable, options = nil)
          @serializable = serializable
          @options = options ? options.dup : {}
        end

        def serializable_hash
          @serializable.serializable_hash(@options.except(:include))
        end

        def serializable_collection
          methods = Array(options[:methods]).map(&:to_s)
          serializable_hash.map do |name, value|
            name = name.to_s
            if methods.include?(name)
              self.class::MethodAttribute.new(name, @serializable, value)
            else
              self.class::Attribute.new(name, @serializable, value)
            end
          end
        end

        def serialize
          require 'builder' unless defined? ::Builder

          options[:indent]  ||= 2
          options[:builder] ||= ::Builder::XmlMarkup.new(indent: options[:indent])

          @builder = options[:builder]
          @builder.instruct! unless options[:skip_instruct]

          root = (options[:root] || @serializable.model_name.element).to_s
          root = ActiveSupport::XmlMini.rename_key(root, options)

          args = [root]
          args << { xmlns: options[:namespace] } if options[:namespace]
          args << { type: options[:type] } if options[:type] && !options[:skip_types]

          @builder.tag!(*args) do
            add_attributes_and_methods
            add_includes
            add_extra_behavior
            add_procs
            yield @builder if block_given?
          end
        end

        private

        def add_extra_behavior
        end

        def add_attributes_and_methods
          serializable_collection.each do |attribute|
            key = ActiveSupport::XmlMini.rename_key(attribute.name, options)
            ActiveSupport::XmlMini.to_tag(key, attribute.value,
                                          options.merge(attribute.decorations))
          end
        end

        def add_includes
          @serializable.send(:serializable_add_includes, options) do |association, records, opts|
            add_associations(association, records, opts)
          end
        end

        # TODO: This can likely be cleaned up to simple use ActiveSupport::XmlMini.to_tag as well.
        def add_associations(association, records, opts)
          merged_options = opts.merge(options.slice(:builder, :indent))
          merged_options[:skip_instruct] = true

          [:skip_types, :dasherize, :camelize].each do |key|
            merged_options[key] = options[key] if merged_options[key].nil? && !options[key].nil?
          end

          if records.respond_to?(:to_ary)
            records = records.to_ary

            tag  = ActiveSupport::XmlMini.rename_key(association.to_s, options)
            type = options[:skip_types] ? { } : { type: "array" }
            association_name = association.to_s.singularize
            merged_options[:root] = association_name

            if records.empty?
              @builder.tag!(tag, type)
            else
              @builder.tag!(tag, type) do
                records.each do |record|
                  if options[:skip_types]
                    record_type = {}
                  else
                    record_class = (record.class.to_s.underscore == association_name) ? nil : record.class.name
                    record_type = { type: record_class }
                  end

                  record.to_xml merged_options.merge(record_type)
                end
              end
            end
          else
            merged_options[:root] = association.to_s

            unless records.class.to_s.underscore == association.to_s
              merged_options[:type] = records.class.name
            end

            records.to_xml merged_options
          end
        end

        def add_procs
          if procs = options.delete(:procs)
            Array(procs).each do |proc|
              if proc.arity == 1
                proc.call(options)
              else
                proc.call(options, @serializable)
              end
            end
          end
        end
      end

      # Returns XML representing the model. Configuration can be
      # passed through +options+.
      #
      # Without any +options+, the returned XML string will include all the
      # model's attributes.
      #
      #   user = User.find(1)
      #   user.to_xml
      #
      #   <?xml version="1.0" encoding="UTF-8"?>
      #   <user>
      #     <id type="integer">1</id>
      #     <name>David</name>
      #     <age type="integer">16</age>
      #     <created-at type="dateTime">2011-01-30T22:29:23Z</created-at>
      #   </user>
      #
      # The <tt>:only</tt> and <tt>:except</tt> options can be used to limit the
      # attributes included, and work similar to the +attributes+ method.
      #
      # To include the result of some method calls on the model use <tt>:methods</tt>.
      #
      # To include associations use <tt>:include</tt>.
      #
      # For further documentation, see <tt>ActiveRecord::Serialization#to_xml</tt>
      def to_xml(options = {}, &block)
        Serializer.new(self, options).serialize(&block)
      end

      # Sets the model +attributes+ from an XML string. Returns +self+.
      #
      #   class Person
      #     include ActiveModel::Serializers::Xml
      #
      #     attr_accessor :name, :age, :awesome
      #
      #     def attributes=(hash)
      #       hash.each do |key, value|
      #         instance_variable_set("@#{key}", value)
      #       end
      #     end
      #
      #     def attributes
      #       instance_values
      #     end
      #   end
      #
      #   xml = { name: 'bob', age: 22, awesome:true }.to_xml
      #   person = Person.new
      #   person.from_xml(xml) # => #<Person:0x007fec5e3b3c40 @age=22, @awesome=true, @name="bob">
      #   person.name          # => "bob"
      #   person.age           # => 22
      #   person.awesome       # => true
      def from_xml(xml)
        self.attributes = Hash.from_xml(xml).values.first
        self
      end
    end
  end
end
