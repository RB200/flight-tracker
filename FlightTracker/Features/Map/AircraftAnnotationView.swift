import MapKit
import UIKit

@MainActor
final class AircraftAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "AircraftAnnotationView"

    private let selectionRing = UIView()
    private let iconImageView = UIImageView()
    private let callsignLabel = UILabel()

    override var isSelected: Bool {
        didSet { updateSelection(animated: true) }
    }

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconImageView.transform = .identity
        iconImageView.alpha = 1
        callsignLabel.text = nil
        selectionRing.alpha = 0
        accessibilityIdentifier = nil
    }

    func apply(_ aircraft: Aircraft, animated: Bool) {
        updateIcon(for: aircraft)
        accessibilityLabel = aircraft.callsign ?? aircraft.icao24.uppercased()
        accessibilityValue = aircraft.isStale ? "Stale aircraft" : "Aircraft"
        accessibilityIdentifier = "aircraft-\(aircraft.icao24)"
        callsignLabel.text = aircraft.callsign
        iconImageView.alpha = aircraft.isStale ? 0.4 : 1

        // SF Symbols' airplane points right at 0 radians; aviation headings use north as 0°.
        let angle = CGFloat(((aircraft.headingDegrees ?? 0) - 90) * .pi / 180)
        let changes = { self.iconImageView.transform = CGAffineTransform(rotationAngle: angle) }
        if animated {
            UIView.animate(withDuration: 0.35, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut], animations: changes)
        } else {
            changes()
        }
    }

    func applyMotion(_ aircraft: Aircraft) {
        iconImageView.alpha = aircraft.isStale ? 0.4 : 1
        let angle = CGFloat(((aircraft.headingDegrees ?? 0) - 90) * .pi / 180)
        iconImageView.transform = CGAffineTransform(rotationAngle: angle)
    }

    private func configure() {
        frame = CGRect(x: 0, y: 0, width: 56, height: 44)
        centerOffset = CGPoint(x: 0, y: -4)
        canShowCallout = false
        collisionMode = .circle
        displayPriority = .defaultHigh
        isAccessibilityElement = true

        selectionRing.frame = CGRect(x: 14, y: 0, width: 28, height: 28)
        selectionRing.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.2)
        selectionRing.layer.borderColor = UIColor.systemBlue.cgColor
        selectionRing.layer.borderWidth = 2
        selectionRing.layer.cornerRadius = 14
        selectionRing.alpha = 0

        let configuration = UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        iconImageView.image = UIImage(systemName: "airplane", withConfiguration: configuration)
        iconImageView.tintColor = .label
        iconImageView.contentMode = .center
        iconImageView.frame = CGRect(x: 14, y: 0, width: 28, height: 28)

        callsignLabel.frame = CGRect(x: 0, y: 28, width: 56, height: 15)
        callsignLabel.font = .monospacedSystemFont(ofSize: 9, weight: .semibold)
        callsignLabel.textAlignment = .center
        callsignLabel.textColor = .label
        callsignLabel.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.72)
        callsignLabel.layer.cornerRadius = 4
        callsignLabel.clipsToBounds = true

        addSubview(selectionRing)
        addSubview(iconImageView)
        addSubview(callsignLabel)
    }

    private func updateSelection(animated: Bool) {
        let changes = {
            self.selectionRing.alpha = self.isSelected ? 1 : 0
            self.callsignLabel.textColor = self.isSelected ? .systemBlue : .label
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: changes)
        } else {
            changes()
        }
    }

    private func updateIcon(for aircraft: Aircraft) {
        let configuration = UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        iconImageView.image = UIImage(systemName: aircraft.aircraftType.systemImage, withConfiguration: configuration)
    }
}
