#import "prelude.typ": *
#import "title.typ": title_page
#import "first-part.typ": first-part
#import "second-part.typ": second-part

#show: thesis_format.with(title_page: { title_page() })

#show: {
  set_text_format(first-part)
  pagebreak()
  set_text_format(second-part)
}
