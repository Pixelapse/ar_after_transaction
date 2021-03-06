require "spec_helper"

class AnExpectedError < Exception
end

class User
  cattr_accessor :test_callbacks, :test_stack
  self.test_stack = []
  self.test_callbacks = []

  after_create :do_it
  def do_it
    self.class.test_callbacks.map{|callback| send(callback)}.last
  end

  def do_after
    after_transaction do
      ActiveRecord::Base.transaction do
        # nested transaction should not cause infinitive recursion
      end
      self.class.test_stack << :after
    end
  end

  def do_normal
    self.class.test_stack << :normal
  end

  def oops
    raise AnExpectedError
  end

  def raise_rollback
    raise ActiveRecord::Rollback
  end
end

describe ARAfterTransaction do
  before do
    User.normally_open_transactions = nil
    User.send(:transactions_open?).should == false
    User.test_stack.clear
    User.test_callbacks.clear
  end

  it "has a VERSION" do
    ARAfterTransaction::VERSION.should =~ /^\d+\.\d+\.\d+$/
  end

  it "executes after a transaction" do
    User.test_callbacks = [:do_after, :do_normal]
    User.create!
    User.test_stack.should == [:normal, :after]
  end

  it "does not execute when transaction was rolled back" do
    User.test_callbacks = [:do_after, :do_normal, :oops]
    lambda{
      User.create!
    }.should raise_error(AnExpectedError)
    User.test_stack.should == [:normal]
  end

  it "does not execute when transaction gets rolled back by ActiveRecord::Rollback raised in an after_create callback" do
    User.test_callbacks = [:do_after, :do_normal, :raise_rollback]
    user = User.create!
    User.test_stack.should == [:normal]
  end

  it "does not execute when transaction gets rolled back by ActiveRecord::Rollback outside of the model" do
    User.test_callbacks = [:do_after, :do_normal]
    user = nil
    ActiveRecord::Base.transaction do
      user = User.create!
      raise ActiveRecord::Rollback
    end
    User.test_stack.should == [:normal]
  end

  it "clears transaction callbacks when transaction fails" do
    User.test_callbacks = [:do_after, :do_normal, :oops]
    lambda{
      User.create!
    }.should raise_error(AnExpectedError)
    User.test_callbacks = [:do_normal]
    User.create!
    User.test_stack.should == [:normal, :normal]
  end

  it "executes when no transaction is open" do
    user = User.new
    user.do_after
    user.do_normal
    User.test_stack.should == [:after, :normal]
  end

  it "executes when open transactions are normal" do
    User.normally_open_transactions = 1
    User.test_callbacks = [:do_after, :do_normal]
    User.create!
    User.test_stack.should == [:after, :normal]
  end

  it "does not execute the same callback twice when successful" do
    User.test_callbacks = [:do_after, :do_normal]
    User.create!
    User.create!
    User.test_stack.should == [:normal, :after, :normal, :after]
  end

  it "does not execute the same callback twice when failed" do
    User.test_callbacks = [:do_after, :do_normal, :oops]
    lambda{
      User.create!
    }.should raise_error(AnExpectedError)
    lambda{
      User.create!
    }.should raise_error(AnExpectedError)
    User.test_stack.should == [:normal, :normal]
  end

  it "does not crash with additional options" do
    User.transaction(:requires_new => true){}
  end

  describe :normally_open_transactions do
    it "uses 0 by default" do
      User.normally_open_transactions.should == 0
    end

    it "can set normally open transactions" do
      User.normally_open_transactions = 5
      User.normally_open_transactions.should == 5
    end

    it "sets them globally" do
      User.normally_open_transactions = 5
      ActiveRecord::Base.normally_open_transactions.should == 5
    end
  end
end

describe "A normal ActiveRecord subclass" do
  it "does not get polluted" do
    User.const_defined?(:VERSION).should be_false
    User.const_defined?(:Version).should be_false
  end
end
