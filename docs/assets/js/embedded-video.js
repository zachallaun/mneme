// Auto-embeds raw URLs as <video> tags.
//
// When GitHub encounters a raw URL to a video, it will convert it
// to a <video> tag.
//
// For example:
//
//     <p>https://user-images.githubusercontent.com/EXAMPLE.mp4</p>
//
// will be rendered as
//
//     <video src="https://user-images.githubusercontent.com/EXAMPLE.mp4" ...></video>
//
// This script implements the same thing, but requires that `data-video`
// be present on the <p>:
//
//     <p data-video>https://user-images.githubusercontent.com/EXAMPLE.mp4</p>
//

(() => {

  const MP4_RE = /^https:\/\/.+\.mp4$/

  document.querySelectorAll('p[data-video]').forEach(p => {
    if (p.textContent.search(MP4_RE) !== -1) {
      const url = p.textContent

      const video = document.createElement('video')
      video.src = url
      video.muted = true
      video.autoplay = false
      video.controls = 'controls'
      video.style.width = '100%'

      p.parentElement.replaceChild(video, p)
    }
  })

})()

