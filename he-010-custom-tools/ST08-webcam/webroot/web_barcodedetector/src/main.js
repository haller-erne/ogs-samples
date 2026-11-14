import './style.css'
import { BarcodeDetector, prepareZXingModule } from 'barcode-detector/ponyfill'
import wasmUrl from 'zxing-wasm/reader/zxing_reader.wasm?url'

prepareZXingModule({
  overrides: {
    locateFile: (path, prefix) => path.endsWith('.wasm') ? wasmUrl : prefix + path
  }
})

const OGS = window.OGS || {}
const video = document.querySelector('#webcam')
const divResult = document.querySelector('#qr-reader-results')
const detector = new BarcodeDetector()

let lastResult = ''
let stream = null
let scanTimer = null
let cameraGeneration = 0
let lifecycleStarted = false

function stopCamera() {
  cameraGeneration++
  clearTimeout(scanTimer)
  scanTimer = null
  if (stream) {
    stream.getTracks().forEach(track => track.stop())
    stream = null
  }
  video.srcObject = null
  lastResult = ''
}

async function scanLoop(generation) {
  try {
    if (video.readyState >= video.HAVE_ENOUGH_DATA) {
      const barcodes = await detector.detect(video)
      if (generation !== cameraGeneration) return
      const barcode = barcodes[0]
      if (barcode && barcode.rawValue !== lastResult) {
        lastResult = barcode.rawValue
        console.log('Scan result', barcode.rawValue, barcode)
        OGS.sendScanData(barcode.rawValue, barcode)
      }
    }
  } catch (error) {
    console.error('Barcode detection failed:', error)
  }
  if (generation === cameraGeneration) {
    scanTimer = setTimeout(() => scanLoop(generation), 100)
  }
}

OGS.onInit = function(url) {
  lifecycleStarted = true
  console.log('OGS.onInit called:', url, OGS)
}
OGS.onShow = function() {
  lifecycleStarted = true
  console.log('OGS.onShow called!')
  OGS.Emit({ cmd: 'OnShow' })
}
OGS.onHide = function() {
  console.log('OGS.onHide called!')
  stopCamera()
  OGS.Emit({ cmd: 'OnHide' })
}
OGS.Emit = function(obj) {
  if (OGS.SendCmd) {
    OGS.SendCmd(JSON.stringify(obj))
  } else {
    console.log('OGS.Send():', obj)
    if (obj.cmd === 'OnShow') OGS.StartCamera('environment')
  }
}
OGS.sendScanData = function(decodedText, decodedResult) {
  OGS.Emit({ cmd: 'OnScanData', decodedText, decodedResult })
}
OGS.StartCamera = async function(facingMode) {
  console.log('OGS.StartCamera()', facingMode)
  stopCamera()
  const generation = cameraGeneration
  try {
    const newStream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode }
    })
    if (generation !== cameraGeneration) {
      newStream.getTracks().forEach(track => track.stop())
      return
    }
    stream = newStream
    video.srcObject = stream
    await video.play()
    if (generation === cameraGeneration) scanLoop(generation)
  } catch (error) {
    if (generation === cameraGeneration) {
      stopCamera()
      console.error('Unable to start camera:', error)
    }
  }
}
OGS.ShowScanResult = function(cmd) {
  console.log('OGS.ShowScanResult()', cmd)
  const result = JSON.parse(cmd)
  divResult.textContent = result.decodedText
  divResult.style.color = result.ret <= 0 ? 'red' : 'black'
}

window.OGS = OGS

function startStandalone() {
  if (!OGS.SendCmd && !lifecycleStarted) {
    OGS.onInit(window.location.href)
    OGS.onShow()
  }
}

if (document.readyState === 'complete') {
  startStandalone()
} else {
  window.addEventListener('load', startStandalone, { once: true })
}