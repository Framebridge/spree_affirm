require 'spec_helper'

describe Spree::AffirmController do
  let(:user) { FactoryGirl.create(:user) }
  let(:checkout) { FactoryGirl.build(:affirm_checkout) }
  let(:bad_billing_checkout) { FactoryGirl.build(:affirm_checkout, billing_address_mismatch: true) }
  let(:bad_shipping_checkout) { FactoryGirl.build(:affirm_checkout, shipping_address_mismatch: true) }
  let(:bad_email_checkout) { FactoryGirl.build(:affirm_checkout, billing_email_mismatch: true) }


  describe "POST confirm" do

    def post_request(token, payment_id)
      post :confirm, checkout_token: token, payment_method_id: payment_id, use_route: 'spree'
    end

    before do
      controller.stub authenticate_spree_user!: true
      controller.stub spree_current_user: user

      stub_request(:post, "https://sandbox.affirm.com/api/v2/charges/").
      to_return(status: 200, body: {
        id: "ALO4-UVGR",
        created: "2016-03-18T19:19:04Z",
        currency: "USD",
        amount: (checkout.order.total * 100).to_i,
        auth_hold: (checkout.order.total * 100).to_i,
        payable: 0,
        void: false,
        pending: true,
        expires: "2016-04-18T19:19:04Z",
        order_id: "JKLM4321",
        events:[
           {
              created: "2014-03-20T14:00:33Z",
              currency: "USD",
              id: "UI1ZOXSXQ44QUXQL",
              transaction_id: "TpR3Xrx8TkvuGio0",
              type: "auth"
           }
        ],
        details:{
           items:{
              sweatera92123:{
                 sku: "sweater-a92123",
                 display_name: "Sweater",
                 qty:1,
                 item_type: "physical",
                 item_image_url: "http://placehold.it/350x150",
                 item_url: "http://placehold.it/350x150",
                 unit_price: 5000
              }
           },
           order_id: "JKLM4321",
           shipping_amount: 0,
           tax_amount: checkout.order.tax_total,
           shipping:{
              name:{
                 full: "John Doe"
              },
              address:{
                 line1: "325 Pacific Ave",
                 city: "San Francisco",
                 state: "CA",
                 zipcode: "94112",
                 country: "USA"
              }
           },
           discounts: {
             RETURN5: {
               discount_amount:    500,
               discount_display_name: "Returning customer 5% discount"
             },
             PRESDAY10: {
               discount_amount:    1000,
               discount_display_name: "President's Day 10% off"
             }
           }
        }
      }.to_json)
    end

    context "when the checkout matches the order" do
      before do
        Spree::AffirmCheckout.stub new: checkout
        controller.stub current_order: checkout.order
      end

      context "when no checkout_token is provided" do
        it "redirects to the current order state" do
          post_request(nil, nil)
          expect(response).to redirect_to(controller.checkout_state_path(checkout.order.state))
        end
      end

      context "when the order is complete" do
        before do
          checkout.order.state = 'complete'
        end
        it "redirects to the current order state" do
          post_request '123456789', checkout.payment_method.id
          expect(response).to redirect_to(controller.order_path(checkout.order))
        end
      end

      context "when the order state is payment" do
        before do
          checkout.order.state = 'payment'
        end

        it "creates a new payment" do
          post_request checkout.order.token, checkout.payment_method.id

          expect(checkout.order.payments.first.source).to eq(checkout)
        end

        it "transitions to complete if confirmation is not required" do
          checkout.order.stub confirmation_required?: false
          post_request checkout.order.token, checkout.payment_method.id

          expect(checkout.order.state).to eq("complete")
        end

        it "transitions to confirm if confirmation is required" do
          checkout.order.stub confirmation_required?: true
          post_request checkout.order.token, checkout.payment_method.id

          expect(checkout.order.reload.state).to eq("confirm")
        end

        it "does not advance an order if it's already in the confirm state" do
          checkout.order.state = 'confirm'
          checkout.order.save!
          checkout.order.stub confirmation_required?: true
          post_request checkout.order.token, checkout.payment_method.id

          expect(checkout.order.reload.state).to eq("confirm")
        end
      end

    end

    context "when the billing_address does not match the order" do
      before do
        Spree::AffirmCheckout.stub new: bad_billing_checkout
        state = FactoryGirl.create(:state, abbr: bad_billing_checkout.details['billing']['address']['region1_code'])
        Spree::State.stub find_by_abbr: state, find_by_name: state
        controller.stub current_order: bad_billing_checkout.order
      end

      it "creates a new address record for the order" do
        _old_billing_address = bad_billing_checkout.order.bill_address
        post_request '12345789', bad_billing_checkout.payment_method.id

        expect(bad_billing_checkout.order.bill_address).not_to be(_old_billing_address)
        expect(bad_billing_checkout.valid?).to be(true)
      end
    end


    context "when the shipping_address does not match the order" do
      before do
        Spree::AffirmCheckout.stub new: bad_shipping_checkout
        state = FactoryGirl.create(:state, abbr: bad_shipping_checkout.details['shipping']['address']['region1_code'])
        Spree::State.stub find_by_abbr: state, find_by_name: state
        controller.stub current_order: bad_shipping_checkout.order
      end

      it "creates a new address record for the order" do
        _old_shipping_address = bad_shipping_checkout.order.ship_address
        post_request '12345789', bad_shipping_checkout.payment_method.id

        expect(bad_shipping_checkout.order.ship_address).not_to be(_old_shipping_address)
        expect(bad_shipping_checkout.valid?).to be(true)
      end
    end



    context "when the billing_email does not match the order" do
      before do
        Spree::AffirmCheckout.stub new: bad_email_checkout
        controller.stub current_order: bad_email_checkout.order
      end

      it "updates the billing_email on the order" do
        _old_email = bad_email_checkout.order.email
        post_request '12345789', bad_email_checkout.payment_method.id

        expect(bad_email_checkout.order.email).not_to be(_old_email)
        expect(bad_email_checkout.valid?).to be(true)
      end
    end


    context "there is no current order" do
      before(:each) do
        controller.stub current_order: nil
      end

      it "raises an ActiveRecord::RecordNotFound error" do
        expect do
          post_request nil, nil
        end.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
