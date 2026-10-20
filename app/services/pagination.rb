module Pagination
  DEFAULT_PER_PAGE = 20
  MAX_PER_PAGE = 100

  Page = Data.define(:number, :per_page, :total_count, :total_pages) do
    def first? = number == 1
    def last? = number == total_pages
    def previous = first? ? nil : number - 1
    def next = last? ? nil : number + 1
  end

  module_function

  def call(scope, page:, per_page: DEFAULT_PER_PAGE)
    per_page = per_page.to_i.clamp(1, MAX_PER_PAGE)
    total_count = scope.except(:limit, :offset).count
    total_pages = [ (total_count.to_f / per_page).ceil, 1 ].max
    number = page.to_i.clamp(1, total_pages)
    records = scope.limit(per_page).offset((number - 1) * per_page).to_a
    [ records, Page.new(number:, per_page:, total_count:, total_pages:) ]
  end
end
