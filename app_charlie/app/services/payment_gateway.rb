class PaymentGateway
  LOG_PATH = -> { Rails.root.join("log/payments.log") }

  def self.hold(payment)
    new(payment).hold
  end

  def self.charge(payment)
    new(payment).charge
  end

  def self.refund(payment)
    new(payment).refund
  end

  def initialize(payment)
    @payment = payment
  end

  def hold
    card = @payment.request.client.default_card
    return { success: false, error: "No default card" } unless card

    @payment.update!(card: card)
    @payment.hold!
    log("hold", "payment_id=#{@payment.id} amount=#{@payment.amount_cents} card=*#{card.last_four}")
    { success: true }
  end

  def charge
    return { success: false, error: "Payment not held" } unless @payment.status == "held"

    @payment.charge!
    log("charge", "payment_id=#{@payment.id} amount=#{@payment.amount_cents} card=*#{@payment.card.last_four}")
    { success: true }
  end

  def refund
    return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)

    @payment.refund!
    log("refund", "payment_id=#{@payment.id} amount=#{@payment.amount_cents}")
    { success: true }
  end

  private

  def log(action, message)
    File.open(self.class::LOG_PATH.call, "a") do |f|
      f.puts "[PAYMENT] action=#{action} #{message} at=#{Time.current.iso8601}"
    end
  end
end
