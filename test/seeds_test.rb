require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  SEED_FILE = Rails.root.join("db/seeds/communes_metropole_lyon.json")

  test "les codes INSEE du fichier de seed sont uniques" do
    codes = seed_data.map { it.fetch("code") }

    assert_equal codes.uniq.size, codes.size
  end

  test "db:seed charge toutes les communes du fichier et est idempotent" do
    Commune.delete_all

    2.times { Rails.application.load_seed }

    assert_equal seed_data.size, Commune.count
    assert_equal seed_data.map { it.fetch("code") }.sort, Commune.order(:code_insee).pluck(:code_insee)
  end

  private
    def seed_data
      JSON.parse(SEED_FILE.read)
    end
end
