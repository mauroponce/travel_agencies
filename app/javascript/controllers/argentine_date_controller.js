import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "iso", "picker"]
  static values = { datetime: Boolean }

  connect() { this.update() }

  update() {
    const text = this.displayTarget.value.trim()
    if (!text) {
      this.displayTarget.value = ""
      this.displayTarget.setCustomValidity("")
      this.isoTarget.value = this.pickerTarget.value = ""
      return
    }
    const match = text.match(this.datetimeValue
      ? /^(\d{2})\/(\d{2})\/(\d{4}) (\d{2}):(\d{2})$/
      : /^(\d{2})\/(\d{2})\/(\d{4})$/)
    let valid = false
    let iso = ""
    if (match) {
      const [, day, month, year, hour = "00", minute = "00"] = match
      const date = new Date(0)
      date.setUTCFullYear(Number(year), Number(month) - 1, Number(day))
      valid = Number(year) > 0 && date.getUTCFullYear() === Number(year) &&
        date.getUTCMonth() === Number(month) - 1 && date.getUTCDate() === Number(day) &&
        Number(hour) < 24 && Number(minute) < 60
      iso = `${year}-${month}-${day}${this.datetimeValue ? `T${hour}:${minute}` : ""}`
    }
    this.displayTarget.setCustomValidity(valid ? "" : `Ingresá una fecha válida en formato ${this.datetimeValue ? "DD/MM/AAAA HH:mm" : "DD/MM/AAAA"}.`)
    this.isoTarget.value = this.pickerTarget.value = valid ? iso : ""
  }

  choose() {
    const value = this.pickerTarget.value
    if (!value) this.displayTarget.value = ""
    else {
      const [date, time] = value.split("T")
      const [year, month, day] = date.split("-")
      this.displayTarget.value = `${day}/${month}/${year}${this.datetimeValue ? ` ${time.slice(0, 5)}` : ""}`
    }
    this.update()
    this.displayTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  open() {
    if (this.pickerTarget.showPicker) this.pickerTarget.showPicker()
    else { this.pickerTarget.focus(); this.pickerTarget.click() }
  }
}
