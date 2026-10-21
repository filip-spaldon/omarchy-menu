pragma Singleton
import QtQuick
QtObject {
  property QtObject applications: QtObject { property var values: typeof harnessFixtures === "string" ? JSON.parse(harnessFixtures).apps : [] }
  function heuristicLookup(key) { return null }
}
