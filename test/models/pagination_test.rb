require "test_helper"

class PaginationTest < ActiveSupport::TestCase
  test "offset pages remain deterministic when every primary sort value is tied" do
    timestamp = Time.current.change(usec: 0)
    companies = 5.times.map do |index|
      company = Company.create!(name: "Nombre empatado", slug: "paginada-#{index}-#{SecureRandom.hex(2)}")
      company.update_columns(created_at: timestamp, updated_at: timestamp)
      company
    end
    scope = Company.where(id: companies.map(&:id)).order(created_at: :desc, id: :desc)

    first, first_page = Pagination.call(scope, page: 1, per_page: 2)
    second, second_page = Pagination.call(scope, page: 2, per_page: 2)
    third, third_page = Pagination.call(scope, page: 3, per_page: 2)

    expected = companies.map(&:id).sort.reverse
    assert_equal expected, [ first, second, third ].flatten.map(&:id)
    assert_equal 5, first_page.total_count
    assert_equal 3, first_page.total_pages
    assert_equal [ 1, 2, 3 ], [ first_page.number, second_page.number, third_page.number ]
  end
end
