
#let title_page(
  about: [по дисциплине],
  subject: ["Информационные системы"],
  theme: [Сервис для аренды инструментов],
  student: [Черемисова М.А., № Р3310, Силаев З.А, № P3310],
  university_manager: [Тюрин И. Н.],
  date: "20.04.2025",
) = [
  // Центрированный блок
  #align(center)[
    #text(weight: "bold")[Министерство науки и высшего образования РФ]

    #text(weight: "bold")[Федеральное государственное автономное образовательное учреждение высшего образования]

    #text(weight: "bold")[«Национальный исследовательский университет ИТМО»]

    #text[(Университет ИТМО)]
    #v(2em)

    #text(weight: "bold")[Факультет Программной инженерии и компьютерной техники]

    #text(weight: "bold")[Образовательная программа Системное и прикладное программное обеспечение]

    #text(size: 16pt, weight: "bold")[КУРСОВАЯ РАБОТА]
    #v(0em)
    #text(about)
    #v(0.5em)
    #text(subject)
    #v(1em)
  ]

  // Левый край (для информации)
  #align(left + horizon)[
    #text(weight: "bold")[Тема задания:] #text(theme)

    #text(weight: "bold")[Обучающиеся:] #text(student)

    #text(weight: "bold")[Преподаватель:] #text(university_manager)
  ]

  #v(3cm)

  // Центрированный блок (для даты и места)

  #align(center + bottom)[
    #text[Санкт-Петербург]

    #text[2025]
  ]
]