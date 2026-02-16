import AsyncAlgorithms

actor Translator {

  let eventChannel = AsyncChannel<String>()
  var eventIndex = 1

  func clInput(line: String) async {
    await eventChannel.send(line)
  }

  func process(line: String) -> String? {
    line
  }

  func doHandshake() {
    
  }

}
