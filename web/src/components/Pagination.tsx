interface Props {
  page: number;
  totalPages: number;
  onChange: (page: number) => void;
}

type PageItem = number | "gap";

function pageItems(current: number, total: number): PageItem[] {
  if (total <= 7) {
    return Array.from({ length: total }, (_, index) => index + 1);
  }

  const pages = new Set<number>([1, total, current - 1, current, current + 1]);
  if (current <= 3) {
    pages.add(2).add(3).add(4);
  }
  if (current >= total - 2) {
    pages.add(total - 1).add(total - 2).add(total - 3);
  }

  const ordered = [...pages]
    .filter((page) => page >= 1 && page <= total)
    .sort((a, b) => a - b);

  const items: PageItem[] = [];
  let previous = 0;
  for (const page of ordered) {
    if (page - previous > 1) items.push("gap");
    items.push(page);
    previous = page;
  }
  return items;
}

export function Pagination({ page, totalPages, onChange }: Props) {
  if (totalPages <= 1) return null;

  return (
    <nav className="pagination" aria-label="Recipe pages">
      <button
        type="button"
        className="page-arrow"
        onClick={() => onChange(page - 1)}
        disabled={page === 1}
        aria-label="Previous page"
      >
        <span aria-hidden="true">←</span>
        <span className="page-arrow-label">Previous</span>
      </button>

      <ol className="page-list">
        {pageItems(page, totalPages).map((item, index) =>
          item === "gap" ? (
            <li key={`gap-${index}`} className="page-gap" aria-hidden="true">
              …
            </li>
          ) : (
            <li key={item}>
              <button
                type="button"
                className={item === page ? "page-button active" : "page-button"}
                aria-current={item === page ? "page" : undefined}
                aria-label={`Page ${item}`}
                onClick={() => onChange(item)}
              >
                {item}
              </button>
            </li>
          ),
        )}
      </ol>

      <button
        type="button"
        className="page-arrow"
        onClick={() => onChange(page + 1)}
        disabled={page === totalPages}
        aria-label="Next page"
      >
        <span className="page-arrow-label">Next</span>
        <span aria-hidden="true">→</span>
      </button>
    </nav>
  );
}
