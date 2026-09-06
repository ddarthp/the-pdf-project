/// How a scanned page is treated once it has been straightened.
enum ScanFilter {
  /// Left as photographed.
  colour('Colour'),

  /// Every pixel by its brightness alone.
  greyscale('Greyscale'),

  /// Two tones, for text on paper. The smallest files, and the most legible
  /// for a document that was only ever ink on white.
  blackAndWhite('Black & white'),

  /// Colour, with the paper pushed towards white and the ink towards black —
  /// what a photograph of a page usually needs to read like a scan.
  enhance('Enhance');

  const ScanFilter(this.label);

  final String label;
}
