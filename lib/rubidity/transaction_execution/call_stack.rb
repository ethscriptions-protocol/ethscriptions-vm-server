class CallStack
  include ContractErrors
  
  attr_reader :push_count, :all_frames
  
  # TODO: set max stack depth (including internal calls)
  # Verify this doesn't affect the past
  # MAX_CALL_COUNT = 400

  def initialize(transaction_context)
    @frames = []
    @all_frames = []
    @push_count = 0
    @transaction_context = transaction_context
  end

  def current_frame
    @frames.last
  end
  
  def in_low_level_call_context(new_call_level)
    new_call_level.to_sym == :low || @frames.any? do |frame|
      frame.call_level.to_sym == :low
    end
  end
  
  def in_read_only_context?(call)
    call.read_only? || @frames.any?(&:read_only?)
  end
  
  def execute_in_new_frame(
    call_level: :high,
    to_contract_address: nil,
    to_contract_init_code_hash: nil,
    function: nil,
    args: {},
    type:,
    salt: nil
  )
    TransactionContext.log_call("ExternalContractCall", "ExternalContractCall", function) do
      TransactionContext.increment_gas("ExternalContractCall")
      
      from_address = @push_count.zero? ?
        @transaction_context.tx_origin :
        current_frame.effective_contract.address
      
      from_address = TypedVariable.validated_value(:address, from_address)
      to_contract_init_code_hash = TypedVariable.validated_value(
        :bytes32,
        to_contract_init_code_hash
      )
      to_contract_address = TypedVariable.validated_value(:address, to_contract_address, allow_nil: true)
      
      current_transaction = @transaction_context.current_transaction
        
      call = @transaction_context.current_transaction.contract_calls.build(
        call_stack: self,
        call_level: call_level,
        in_low_level_call_context: in_low_level_call_context(call_level),
        to_contract_address: to_contract_address,
        to_contract_init_code_hash: to_contract_init_code_hash,
        function: function,
        args: args,
        call_type: type,
        salt: salt,
        internal_transaction_index: @push_count,
        from_address: from_address,
        block_number: current_transaction.block_number,
        block_blockhash: current_transaction.block_blockhash,
        block_timestamp: current_transaction.block_timestamp,
        transaction_index: current_transaction.transaction_index,
        start_time: Time.current
      )
      
      @transaction_context.set(current_call: call) do
        execute_in_frame(call)
      end
    end
  end
  
  private
  
  def execute_in_frame(call)
    push(call)
    
    current_frame.execute!
  ensure
    pop
  end
  
  def push(frame)
    @frames.push(frame)
    @all_frames.push(frame)
    
    @push_count += 1
  end

  def pop
    @frames.pop
  end
end
