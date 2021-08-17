function get(url, successFn, failFn) {
    var request = new XMLHttpRequest()
    request.open("GET", url, true);
    request.onreadystatechange = function () {
        if (request.readyState === XMLHttpRequest.DONE) {
            if (request.status === 200) {
                successFn(request);
            } else {
                failFn(request);
            }
        }
    }
    request.send(null)
}

function showMardownFile(responseText, file) {
    var converter = new showdown.Converter();
    converter.setOption("customizedHeaderId", "true")
    converter.setOption("ghCompatibleHeaderId", "true")
    document.getElementById("div-file-contents").innerHTML = converter.makeHtml(responseText);

    // Show file name
    document.getElementById("h1-file-name").innerText = file;
    // Generate table of contents
    var h2Elements = document.getElementById("div-file-contents").getElementsByTagName("h2")
    var sampleToc = document.getElementById("link-sample-toc")
    var toc = document.getElementById("div-toc")
    for (var i = 0; i < h2Elements.length; i++) {
        var clone = sampleToc.cloneNode(true)
        clone.href = "#" + h2Elements[i].id
        clone.innerText = h2Elements[i].id
        toc.appendChild(clone)
        toc.innerHTML += "<br />"
    }

    document.getElementById("div-full-file-contents").hidden = false;
}

document.addEventListener("DOMContentLoaded", function () {
    // Show directory
    get(new URL("directory.html.frag", document.location).href, function(request) {
        document.getElementById("div-directory").innerHTML = request.responseText;
    }, function(request) {
        document.getElementById("div-directory").innerText = "Failed to get directory.html.frag"
    });

    const params = new URLSearchParams(window.location.search);
    const file = params.get("file")
    if (!file) {
        return;
    }
    if (!file.endsWith(".md")) {
        document.body.innerText = "Invalid param for file";
        return;
    }
    get(new URL(file, document.location).href, function (request) {
        showMardownFile(request.responseText, file);
    }, function (request) {
        document.body.innerText = request.status + " " + request.statusText
    })
});
