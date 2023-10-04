module RubidityInterpreter
  class RubidityInterpreterTypeError < StandardError; end
  
  def self.build_implementation_class_from_code_string(filename, code_string)
    Builder.new.instance_eval(code_string, filename + ".rubidity", 1)
  end
  
  def self.build_implementation_class_from_file(filename)
    filename = filename.sub(/\.rubidity$/, "") + ".rubidity"
    
    full_name = Rails.root.join("app/models/contracts_rubidity/", filename)
    
    code_string = IO.read(full_name)

    Builder.new.instance_eval(code_string, filename, 1)
  end
  
  def self.migrate
    Dir.glob(Rails.root.join("app/models/contracts/*.rb")).each do |file_path|
      old_content = File.read(file_path)
    
      # Extract class name
      class_name = old_content.match(/class Contracts::(\w+)/)[1]
    
      # Extract dependencies
      dependencies = old_content.scan(/is :(\w+)/).flatten
      
      is_statement = nil
      
      if dependencies.one?
        is_statement = "is: :#{dependencies.first}"
      elsif dependencies.many?
        is_statement = "is: [#{dependencies.join(', ')}]"
      end
        
      is_abstract = old_content.match(/\s*abstract$/)
      
      old_content = old_content.gsub(/\n.*abstract\n.*/, '')
      abstract_string = is_abstract ? "abstract: true" : nil
      
      modifiers = [
        ":#{class_name}",
        is_statement,
        abstract_string,
      ].compact
      
      old_content = old_content.gsub(/\n.*pragma.*\n.*/, '')
      
      new_content = old_content
        .gsub(/\n\s*is.*\n*/, '')
        # .gsub(/class Contracts::#{class_name}.*$/, "contract :#{class_name}#{is_statement}#{abstract_string}do")
        .gsub(/class Contracts::#{class_name}.*$/, "contract #{modifiers.join(', ')} do")
        
        # .gsub(/function :(\w+), \{(.+?)\}, :public/, 'function :\1, {\2}, :public')
        # .gsub(/constructor\(/, 'constructor(')
    
      # Add pragma and import statements
      new_content = "pragma :rubidity, \"1.0.0\"\n\n" + dependencies.map { |dep| "import './#{dep}.rubidity'" }.join("\n") + "\n\n" + new_content
    
      new_content = new_content.gsub("\n\n\n", "\n")
      
      # Write new content to new file
      new_file_path = Rails.root.join('app/models/contracts_rubidity/', "#{class_name}.rubidity")
      File.write(new_file_path, new_content)
    end
    
  end
  
  def self.build_valid_contracts
    files = Dir.glob(Rails.root.join("app/models/contracts_rubidity/*.rubidity"))
    
    files.each.with_object({}) do |file, hsh|
      klass = build_implementation_class_from_file(file)
      hsh[klass.name] = klass
    end.with_indifferent_access
  end
  
  def self.normalize_code
    file_path = "/Users/tom/Dropbox (Personal)/db-src/ethscriptions-vm-server/app/models/contracts_rubidity/ERC20V2.rubidity"
  
    code = File.read(file_path)
    tree = Unparser.parse(code)
  
    normalized_code = Unparser.unparse(tree)
  
    normalized_code
  end
  
  class Builder < BasicObject
    def initialize
      @available_contracts = {}.with_indifferent_access
      @pragma_set = false
      define_const_missing_for_instance
    end
    
    def contract(name, is: [], abstract: false, &block)
      unless @pragma_set
        raise "You must set a pragma before defining a contract."
      end
      
      available_contracts = @available_contracts
      
      implementation_klass = ::Class.new(::ContractImplementation) do
        ::Array.wrap(is).each do |dep|
          unless dep_obj = available_contracts[dep.name]
            raise "Dependency #{dep} is not available."
          end
          self.parent_contracts << dep_obj
        end
        self.parent_contracts = self.parent_contracts.uniq
        
        if abstract
          @is_abstract_contract = true
        end
        
        define_singleton_method(:name) do
          name.to_s
        end
      end
      
      implementation_klass.instance_variable_set(:@available_contracts, @available_contracts.dup)
      
      @available_contracts[name] = implementation_klass

      implementation_klass.tap do |klass|
        klass.instance_eval(&block)
      end
    end
    
    def import(file_path)
      base_dir = "app/models/contracts_rubidity/"

      absolute_path = file_path.start_with?("./") ? ::File.join(base_dir, file_path[2..]) : file_path
    
      content = ::File.read(absolute_path)
      instance_eval(content)
    end
    
    def pragma(lang, version)
      if lang != :rubidity
        raise "Only rubidity is supported."
      end
      
      if version != "1.0.0"
        raise "Only version 1.0.0 is supported."
      end
      
      @pragma_set = true
    end
    
    # def define_const_missing_for_class(klass, current_binding)
    #   singleton_class = (class << klass; class << self; self; end; end)
    #   singleton_class = (class << klass; self; end)

    #   singleton_class.send(:define_method, :const_missing) do |name|
    #     if @available_contracts[name]
    #       # Use the binding to get the instance of the new class
    #       instance = eval('self', current_binding)
  
    #       ContractProxy.new(instance, name)
    #     else
    #       super(name)
    #     end
    #   end
    # end
    
    def define_const_missing_for_instance
      available_contracts = @available_contracts

      singleton_class = (class << self; class << self; self; end; end)
      
      singleton_class.send(:define_method, :const_missing) do |name|
        if available_contracts[name] && ::TransactionContext.current_contract
          # pp name
          # binding.pry
          ::TransactionContext.current_contract.implementation.send(name)
        else
          # name.to_sym
          super(name)
        end
      end
    end
    
    # def self.const_missing(name)
    #   # pp ancestors
    #   pp caller
    #   name.to_sym
    # end
  end
end


# dummy_code_string = <<-CODE
#   contract PublicMintERC20, is: [ERC20] do
#   # contract PublicMintERC20, is: [ERC20, Ownable] do
#     constructor(name: :string) {
#       ERC20.constructor(name: name, symbol: "symbol", decimals: 18)
#     }
    
#     function :mint, { amount: :uint256 }, :public do
#       _mint(to: msg.sender, amount: amount)
#     end
#   end
# CODE

# Contract.first.get_implementation_from_code_string(dummy_code_string)
