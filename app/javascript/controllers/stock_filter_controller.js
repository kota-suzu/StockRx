import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="stock-filter"
export default class extends Controller {
  static targets = [ "thresholdContainer" ]

  connect() {
    this.toggleThreshold()
  }

  toggleThreshold() {
    const stockFilterValue = this.element.value
    
    if (stockFilterValue === 'low_stock') {
      this.thresholdContainerTarget.style.display = 'flex'
    } else {
      this.thresholdContainerTarget.style.display = 'none'
    }
  }
}