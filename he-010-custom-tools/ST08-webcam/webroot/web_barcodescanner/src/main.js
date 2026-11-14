import './style.css'
import { Html5QrcodeScanner, Html5Qrcode } from 'html5-qrcode'
let OGS = {}

var resultContainer = document.getElementById('qr-reader-results');
var lastResult, countResults = 0;

function onScanSuccess(decodedText, decodedResult) {
    if (decodedText !== lastResult) {
        ++countResults;
        lastResult = decodedText;
        // Handle on success condition with the decoded message.
        console.log(`Scan result ${decodedText}`, decodedResult);
        OGS.sendScanData(decodedText, decodedResult);
    }
}

var config = { 
  fps: 10, 
  qrbox: 600,
  showTorchButtonIfSupported: true,
  showZoomSliderIfSupported: true,
  defaultZoomValueIfSupported: 2  
};

//var html5QrcodeScanner = new Html5QrcodeScanner("qr-reader", config);
//html5QrcodeScanner.render(onScanSuccess);

const html5QrCode = new Html5Qrcode("qr-reader", {});
const divResult = document.querySelector('#qr-reader-results')
/*
// If you want to prefer front camera
html5QrCode.start({ facingMode: "user" }, config, qrCodeSuccessCallback);
// If you want to prefer back camera
html5QrCode.start({ facingMode: "environment" }, config, qrCodeSuccessCallback);
// Select front camera or fail with `OverconstrainedError`.
html5QrCode.start({ facingMode: { exact: "user"} }, config, qrCodeSuccessCallback);
// Select back camera or fail with `OverconstrainedError`.
html5QrCode.start({ facingMode: { exact: "environment"} }, config, qrCodeSuccessCallback);
*/

OGS.onInit = function(url) {
	console.log("OGS.onInit called: ", url, OGS);
	//OGS.SendCmd('{ "cmd":"get-version" }');
}
OGS.onShow = function OGS_onShow() {
	console.log("OGS.onShow called!");
  // hide both div's first
  //divImage.style.display 		= "none"; // "block"
  OGS.Emit({ cmd: 'OnShow' });
	//OGS.UpdateTimer = setTimeout(OGS.sendShowCmd, 200);
}
OGS.onHide = function() {
	console.log("OGS.onHide called!");
	//clearTimeout(OGS.UpdateTimer);
	//OGS.UpdateTimer = null;
  OGS.Emit({ cmd: 'OnHide' });
  // shutdown the camera, if it is running
  html5QrCode.stop();
  lastResult = '';
}
OGS.Emit = function(obj) {
  if (OGS.SendCmd) {
      OGS.SendCmd(JSON.stringify(obj));
  } else {
      console.log('OGS.Send(): ', obj);
      // offline simulation
      if (obj.cmd == 'svg-click') {
          OGS.Update({ nodes: [{name: obj.node, checked: true}] });
      }
  }
}

// JS --> OGS
OGS.sendScanData = function(decodedText, decodedResult)
{
  OGS.Emit({ 
    cmd: 'OnScanData',
    decodedText: decodedText,
    decodedResult: decodedResult 
  });
}

// OGS --> JS
// Custom commands (called from OGS LUA file)
OGS.StartCamera = function(facingMode)
{
	console.log("OGS.StartCamera()", facingMode);
  html5QrCode.start({ facingMode: facingMode }, config, onScanSuccess);
}
OGS.ShowScanResult = function(cmd)
{
	console.log("OGS.ShowScanResult()", cmd);
  let o = JSON.parse(cmd)
  if (o.ret <= 0) {
    divResult.innerHTML = o.decodedText;
    divResult.style.color = "red";
  } else {
    divResult.innerHTML = o.decodedText;
    divResult.style.color = "black";
  }
}

window.OGS = OGS;

