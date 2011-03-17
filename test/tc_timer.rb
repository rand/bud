require 'test_common'

class TemporalBudTest
  include Bud

  state do
    periodic :tik, 0.1
    table :log, [:ident, :time]
  end

  bloom do
    log <= tik 
  end
end


class TestTimer < Test::Unit::TestCase
  def test_timer
    t = TemporalBudTest.new
    t.run_bg
    sleep 3
    t.stop_bg
    assert_operator(2, :<, t.log.length)
    assert_operator(7, :>, t.log.length)
  end
end
