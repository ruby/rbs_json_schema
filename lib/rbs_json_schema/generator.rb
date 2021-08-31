module RBSJsonSchema
  class Generator
    attr_reader :stringify_keys
    attr_reader :output
    attr_reader :stdout
    attr_reader :stderr
    attr_reader :path_decls
    attr_reader :generated_schemas

    Alias = RBS::AST::Declarations::Alias

    def initialize(stringify_keys:, output:, stdout:, stderr:)
      @stringify_keys = stringify_keys ? true : false
      @output = output
      @stdout = stdout
      @stderr = stderr
      @path_decls = {}
      @generated_schemas = {}
    end

    # IMPORTANT: Function invoked to generate RBS from JSON schema
    # Generates RBS from JSON schema after validating options & writes to file/STDOUT
    def generate(uri)
      # Validate options received from CLI
      validate_options()

      @path_decls[uri.path] ||= RBS::AST::Declarations::Module.new(
        name: generate_type_name_for_uri(uri, module_name: true),
        type_params: RBS::AST::Declarations::ModuleTypeParams.empty,
        members: [],
        self_types: [],
        annotations: [],
        location: nil,
        comment: nil
      )
      generate_rbs(uri, read_from_uri(uri))
    end

    # IMPORTANT: Function used to generate AST alias declarations from a URI & a schema document
    def generate_rbs(uri, document)
      # If schema is already generated for a URI, do not re-generate declarations/types
      if fragment = uri.fragment
        # return if fragment.empty? # If fragment is empty, implies top level schema which is always generated since it is the starting point of the algorithm

        if @generated_schemas.dig(uri.path, fragment.empty? ? "#" : fragment) # Check if types have been generated for a particular path & fragment
          return
        end
      else
        if @generated_schemas.dig(uri.path, "#") # Check if types have been generated for a particular path
          return
        end
      end

      unless document.is_a?(Hash)
        raise ValidationError.new(message: "Invalid JSON Schema: #{document}")
      end

      @generated_schemas[uri.path] ||= {}
      if fragment = uri.fragment
        @generated_schemas[uri.path][fragment.empty? ? "#" : fragment] = true
      else
        @generated_schemas[uri.path]["#"] = true
      end
      # Parse & generate declarations from remaining schema content
      decl = Alias.new(
        name: generate_type_name_for_uri(uri), # Normal type name with no prefix
        type: translate_type(uri, document), # Obtain type of alias by parsing the schema document
        annotations: [],
        location: nil,
        comment: nil
      )
      # Append the declaration if & only if the declaration has a valid RBS::Type assigned
      if @path_decls[uri.path]
        @path_decls[uri.path].members << decl if !decl.type.nil?
      else
        @path_decls[uri.path] = RBS::AST::Declarations::Module.new(
          name: generate_type_name_for_uri(uri, module_name: true),
          type_params: RBS::AST::Declarations::ModuleTypeParams.empty,
          members: [],
          self_types: [],
          annotations: [],
          location: nil,
          comment: nil
        )
        @path_decls[uri.path].members << decl if !decl.type.nil?
      end
    end

    def literal_type(literal)
      # Assign literal type
      case literal
      when String, Integer, TrueClass, FalseClass
        RBS::Types::Literal.new(literal: literal, location: nil)
      when nil
        RBS::Types::Bases::Nil.new(location: nil)
      else
        raise ValidationError.new(message: "Unresolved literal found: #{literal}")
      end
    end

    def untyped_type
      RBS::Types::Bases::Any.new(location: nil)
    end

    # Parse JSON schema & return the `RBS::Types` to be assigned
    def translate_type(uri, schema)
      case
      when values = schema["enum"]
        unless values.is_a?(Array)
          raise ValidationError.new(message: "Invalid JSON Schema: enum: #{values}")
        end

        types = values.map { |literal| literal_type(literal) }
        RBS::Types::Union.new(types: types, location: nil)
      when const = schema["const"]
        literal_type(const)
      when schema["type"] == "array" || schema.key?("items")
        case
        when schema["items"].is_a?(Array)
          # tuple
          types = schema["items"].map { |definition| translate_type(uri, definition) }
          RBS::Types::Tuple.new(types: types, location: nil)
        when schema["items"].is_a?(Hash)
          # array
          elem_type = translate_type(uri, schema["items"])
          RBS::BuiltinNames::Array.instance_type(elem_type)
        else
          RBS::BuiltinNames::Array.instance_type(untyped_type)
        end
      when schema["type"] == "object" || schema.key?("properties") || schema.key?("additionalProperties")
        case
        when properties = schema["properties"]
          # @type var properties: json_schema
          fields = properties.each.with_object({}) do |pair, hash|
            # @type var hash: Hash[Symbol, RBS::Types::t]
            key, value = pair

            hash[key.to_sym] = translate_type(uri, value)
          end

          RBS::Types::Record.new(fields: fields, location: nil)
        when prop = schema["additionalProperties"]
          RBS::BuiltinNames::Hash.instance_type(
            RBS::BuiltinNames::String.instance_type,
            translate_type(uri, prop)
          )
        else
          RBS::BuiltinNames::Hash.instance_type(
            RBS::BuiltinNames::String.instance_type,
            untyped_type
          )
        end
      when one_of = schema["oneOf"]
        RBS::Types::Union.new(
          types: one_of.map { |defn| translate_type(uri, defn) },
          location: nil
        )
      when all_of = schema["allOf"]
        RBS::Types::Intersection.new(
          types: all_of.map { |defn| translate_type(uri, defn) },
          location: nil
        )
      when ty = schema["type"]
        case ty
        when "integer"
          RBS::BuiltinNames::Integer.instance_type
        when "number"
          RBS::BuiltinNames::Numeric.instance_type
        when "string"
          RBS::BuiltinNames::String.instance_type
        when "boolean"
          RBS::Types::Bases::Bool.new(location: nil)
        when "null"
          RBS::Types::Bases::Nil.new(location: nil)
        else
          raise ValidationError.new(message: "Invalid JSON Schema: type: #{ty}")
        end
      when ref = schema["$ref"]
        ref_uri =
          begin
            # Parse URI of `$ref`
            URI.parse(schema["$ref"])
          rescue URI::InvalidURIError => _
            raise ValidationError.new(message: "Invalid URI encountered in: $ref = #{ref}")
          end

        resolved_uri = resolve_uri(uri, ref_uri) # Resolve `$ref` URI with respect to current URI
        # Generate AST::Declarations::Alias
        generate_rbs(resolved_uri, read_from_uri(resolved_uri))

        # Assign alias type with appropriate namespace
        RBS::Types::Alias.new(
          name: generate_type_name_for_uri(resolved_uri, namespace: resolved_uri.path != uri.path),
          location: nil
        )
      else
        raise ValidationError.new(message: "Invalid JSON Schema: #{schema.keys.join(", ")}")
      end
    end

    # Read contents from a URI
    def read_from_uri(uri)
      schema_source =
        case uri.scheme
        when "file", nil
          File.read(uri.path)
        when "http", "https"
          Net::HTTP.get(uri)
        else
          raise ValidationError.new(message: "Could not read content from URI: #{uri}")
        end

      schema = JSON.parse(schema_source)

      if (fragment = uri.fragment) && !fragment.empty?
        case
        when fragment.start_with?("/")
          path = fragment.split("/")
          path.shift()

          schema.dig(*path) or
            raise ValidationError.new(message: "JSON pointer doesn't point a schema: #{uri.fragment}")
        else
          raise ValidationError.new(message: "JSON pointer is expected: #{uri.fragment}")
        end
      else
        schema
      end
    end

    # Write output using `RBS::Writer` to a particular `IO`
    def write_output
      # If an output directory is given, open a file & write to it
      if output = self.output
        @path_decls.each do |path, decls|
          name = decls.name.name.to_s.underscore
          file_path = File.join(output, "#{name}.rbs")
          File.open(file_path, 'w') do |io|
            stdout.puts "Writing output to file: #{file_path}"
            RBS::Writer.new(out: io).write([decls])
          end
        end
      # If no output directory is given write to STDOUT
      else
        RBS::Writer.new(out: stdout).write(@path_decls.values)
      end
    end

    # Utility function to assign type name from URI
    private def generate_type_name_for_uri(uri, module_name: false, namespace: false)
      dup_uri = uri.dup # Duplicate URI object for processing
      path = dup_uri.path.split("/").last or raise # Extract path
      path.gsub!(/(.json$)?/, '') # Remove JSON file extension if found
      prefix = path.camelize # prefix is used to write module name, hence converted to camel case

      # Return module_name
      if module_name
        return RBS::TypeName.new(
          name: prefix.to_sym,
          namespace: RBS::Namespace.empty
        )
      end

      name = :t

      if fragment = dup_uri.fragment
        unless fragment.empty?
          fragment[0] = "" if fragment.start_with?("/") # Remove initial slash if present in fragment
          name = fragment.downcase.tr("/", "_")
        end
      end

      # Return type name for type alias
      RBS::TypeName.new(
        name: name.to_sym,
        namespace: namespace ? RBS::Namespace.new(path: [prefix.to_sym], absolute: false) : RBS::Namespace.empty
      )
    end

    # Returns type name with prefixes & appropriate namespace
    private def type_name(name, absolute: nil)
      RBS::TypeName.new(
        name: name.to_sym,
        namespace: absolute ? RBS::Namespace.root : RBS::Namespace.empty
      )
    end

    # Utility function to resolve two URIs
    private def resolve_uri(uri, ref_uri)
      begin
        # Attempt to merge the two URIs
        uri + ref_uri
      rescue URI::BadURIError, ArgumentError => _
        # Raise error in case of invalid URI
        raise ValidationError.new(message: "Could not resolve URI: #{uri} + #{ref_uri}")
      end
    end

    # Validate options given to the CLI
    private def validate_options
      if output = self.output
        path = Pathname(output)
        # Check if a valid directory exists?
        raise ValidationError.new(message: "#{output}: Directory not found!") if !path.directory?
      end
    end
  end
end
