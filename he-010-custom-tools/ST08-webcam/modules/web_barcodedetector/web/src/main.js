import './style.css'
import { BarcodeDetector, prepareZXingModule } from 'barcode-detector/ponyfill'
import wasmUrl from 'zxing-wasm/reader/zxing_reader.wasm?url'

const OGS = window.OGS || {}
const video = document.querySelector('#webcam')
const cameraView = document.querySelector('#camera-view')
const cameraToggle = document.querySelector('#camera-toggle')
const cameraError = document.querySelector('#camera-error')
const divResult = document.querySelector('#qr-reader-results')
let detectorPromise = null

function getDetector() {
  if (!detectorPromise) {
    detectorPromise = fetch(wasmUrl)
      .then(async response => {
        if (!response.ok) throw new Error(`Unable to load barcode decoder: ${response.status}`)
        const contentType = response.headers.get('content-type')?.split(';')[0].trim().toLowerCase()
        if (contentType === 'application/wasm') {
          await response.arrayBuffer()
          prepareZXingModule({
            overrides: { locateFile: (path, prefix) => path.endsWith('.wasm') ? wasmUrl : prefix + path }
          })
        } else {
          const wasmBinary = await response.arrayBuffer()
          prepareZXingModule({ overrides: { wasmBinary: new Uint8Array(wasmBinary) } })
        }
        return new BarcodeDetector({ formats: ['qr_code', 'data_matrix', 'code_128'] })
      })
      .catch(error => {
        detectorPromise = null
        throw error
      })
  }
  return detectorPromise
}

let lastResult = ''
let stream = null
let scanTimer = null
let cameraGeneration = 0
let lifecycleStarted = false
let cameraFacingMode = 'environment'
let isPaused = true

function updatePlaybackState(paused) {
  isPaused = paused
  cameraView.classList.toggle('is-paused', paused)
  const label = paused ? 'Start scanning' : 'Pause scanning'
  cameraToggle.setAttribute('aria-label', label)
  cameraToggle.title = label
}

function pauseCamera() {
  cameraGeneration++
  clearTimeout(scanTimer)
  scanTimer = null
  video.pause()
  updatePlaybackState(true)
  lastResult = ''
}

function stopCamera() {
  pauseCamera()
  cameraToggle.disabled = false
  if (stream) {
    stream.getTracks().forEach(track => track.stop())
    stream = null
  }
  video.srcObject = null
  cameraError.hidden = true
  cameraError.textContent = ''
  lastResult = ''
}

async function scanLoop(generation) {
  if (isPaused || generation !== cameraGeneration) return
  try {
    if (video.readyState >= video.HAVE_ENOUGH_DATA && video.videoWidth && video.videoHeight) {
      const detector = await getDetector()
      if (generation !== cameraGeneration) return
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
  cameraFacingMode = facingMode || 'environment'
}

async function startPlayback() {
  if (cameraToggle.disabled) return
  cameraToggle.disabled = true
  cameraError.hidden = true
  cameraError.textContent = ''
  const generation = cameraGeneration
  try {
    if (!stream) {
      const newStream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: cameraFacingMode }
      })
      if (generation !== cameraGeneration) {
        newStream.getTracks().forEach(track => track.stop())
        return
      }
      stream = newStream
      video.srcObject = stream
    }
    await video.play()
    if (generation === cameraGeneration) {
      updatePlaybackState(false)
      scanLoop(generation)
    }
  } catch (error) {
    if (generation === cameraGeneration) {
      stopCamera()
      console.error('Unable to start camera:', error)
      if (error.name === 'NotAllowedError' || error.name === 'PermissionDeniedError') {
        cameraError.textContent = 'Camera access was denied. Check the camera permissions for this page.'
      } else if (error.name === 'NotFoundError' || error.name === 'DevicesNotFoundError') {
        cameraError.textContent = 'No camera was found. Connect a camera and try again.'
      } else if (!navigator.mediaDevices?.getUserMedia) {
        cameraError.textContent = 'Camera access is unavailable. Use a secure connection or localhost and check browser permissions.'
      } else {
        cameraError.textContent = 'Unable to start the camera. Check that it is connected and not in use by another application.'
      }
      cameraError.hidden = false
    }
  } finally {
    if (generation === cameraGeneration) cameraToggle.disabled = false
  }
}

cameraToggle.addEventListener('click', () => {
  if (isPaused) {
    startPlayback()
  } else {
    pauseCamera()
  }
})

OGS.ShowScanResult = function(cmd) {
  console.log('OGS.ShowScanResult()', cmd)
  const result = JSON.parse(cmd)
  divResult.textContent = result.decodedText
  divResult.style.color = result.ret <= 0 ? 'red' : 'black'
}

window.OGS = OGS

function startStandalone() {
  if (!OGS.SendCmd && !lifecycleStarted) {
    console.info('Running in standalone mode with simulated OGS.')
    OGS.onInit(window.location.href)
    OGS.onShow()
  }
}

if (document.readyState === 'complete') {
  startStandalone()
} else {
  window.addEventListener('load', startStandalone, { once: true })
}