ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Substitue une méthode de classe le temps d'un bloc (minitest 6
    # n'embarque plus minitest/mock). `substitut` : valeur ou callable.
    def stub_classe(classe, methode, substitut)
      original = classe.method(methode)
      remplacement = substitut.respond_to?(:call) ? substitut : ->(*) { substitut }
      classe.singleton_class.silence_redefinition_of_method(methode)
      classe.define_singleton_method(methode) { |*args| remplacement.call(*args) }
      yield
    ensure
      classe.singleton_class.silence_redefinition_of_method(methode)
      classe.define_singleton_method(methode, original)
    end
  end
end
