class ArrayVariable < GenericVariable
  expose :push, :pop, :length, :last, :[], :[]=
  
  MAX_ARRAY_LENGTH = 100
  
  delegate :push, :pop, :length, :last, :[], :[]=, to: :value
  
  def initialize(...)
    super(...)
  end
  
  def serialize
    value.data.map(&:serialize)
  end
  
  def toPackedBytes
    res = value.data.map do |arg|
      bytes = arg.toPackedBytes
      bytes = bytes.value.sub(/\A0x/, '')
    end.join
    
    ::TypedVariable.create(:bytes, "0x" + res)
  end
  
  class Value
    include Exposable
    attr_accessor :value_type, :data
    
    def ==(other)
      return false unless other.is_a?(self.class)
      
      other.value_type == value_type &&
      data.length == other.data.length &&
      data.each.with_index.all? do |item, index|
        item.eq(other.data[index]).value
      end
    end
  
    def initialize(
      initial_value = [],
      value_type:,
      initial_length: nil
    )
      if value_type.mapping? || value_type.array?
        raise VariableTypeError.new("Arrays of mappings or arrays are not supported")
      end
      
      self.value_type = value_type
      self.data = initial_value

      if initial_length
        amount_to_pad = initial_length - data.size
        
        amount_to_pad.times do
          data << TypedVariable.create(value_type)
        end
      end
    end
  
    def [](index)
      index_var = TypedVariable.create_or_validate(:uint256, index)
      
      raise "Index out of bounds" if index_var.gte(length).value
      
      value = data[index_var.value] ||
        TypedVariable.create_or_validate(value_type)
      
      if value_type.is_value_type?
        value.deep_dup
      else
        value
      end
    end
    # wrap_with_logging :[]
  
    def []=(index, value)
      index_var = TypedVariable.create_or_validate(:uint256, index)
      raise "Sparse arrays are not supported" if index_var.gt(length).value
      max_len = TypedVariable.create(:uint256, MAX_ARRAY_LENGTH)
      raise "Max array length is #{MAX_ARRAY_LENGTH}" if index_var.gte(max_len).value

      val_var = TypedVariable.create_or_validate(value_type, value)
      
      if index_var.eq(length).value || self[index_var].ne(val_var).value
        if data[index_var.value].nil? || val_var.type.is_value_type?
          data[index_var.value] = val_var
        else
          data[index_var.value].value = val_var.value
        end
      end
      
      data[index_var.value]
    end
    # wrap_with_logging :[]=
    
    def push(value)
      next_index = data.size
      
      self.[]=(next_index, value)
      NullVariable.instance
    end
    # wrap_with_logging :push
    
    # TODO: In Solidity this returns null
    def pop
      TypedVariable.create(value_type, data.pop.value)
    end
    # wrap_with_logging :pop
    
    def length
      TypedVariable.create(:uint256, data.length)
    end
    # wrap_with_logging :length
    
    def last
      self.[](data.length - 1)
    end
    # wrap_with_logging :last
  end
end
