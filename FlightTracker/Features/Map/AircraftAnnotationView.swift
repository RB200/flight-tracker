import MapKit
import UIKit

@MainActor
final class AircraftAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "AircraftAnnotationView"

    private let selectionRing = UIView()
    private let iconImageView = UIImageView()
    private let callsignLabel = UILabel()
    private var isStale = false
    private(set) var isVisuallyHighlighted = false

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
        isStale = false
        updateSelection(animated: false)
        accessibilityIdentifier = nil
    }

    func apply(_ aircraft: Aircraft, animated: Bool) {
        updateIcon(for: aircraft)
        accessibilityLabel = aircraft.callsign ?? aircraft.icao24.uppercased()
        accessibilityValue = aircraft.isStale ? "Stale aircraft" : "Aircraft"
        accessibilityIdentifier = "aircraft-\(aircraft.icao24)"
        callsignLabel.text = aircraft.callsign
        isStale = aircraft.isStale
        iconImageView.alpha = isSelected ? 1 : (isStale ? 0.4 : 1)

        // SF Symbols' airplane points right at 0 radians; aviation headings use north as 0°.
        let angle = CGFloat(((aircraft.headingDegrees ?? 0) - 90) * .pi / 180)
        let changes = { self.iconImageView.transform = CGAffineTransform(rotationAngle: angle) }
        if animated {
            UIView.animate(withDuration: 0.35, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut], animations: changes)
        } else {
            changes()
        }
        updateSelection(animated: false)
    }

    func applyMotion(_ aircraft: Aircraft) {
        isStale = aircraft.isStale
        iconImageView.alpha = isSelected ? 1 : (isStale ? 0.4 : 1)
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

        selectionRing.frame = CGRect(x: 10, y: -4, width: 36, height: 36)
        selectionRing.backgroundColor = .systemBlue
        selectionRing.layer.borderColor = UIColor.white.cgColor
        selectionRing.layer.borderWidth = 2
        selectionRing.layer.cornerRadius = 18
        selectionRing.layer.shadowColor = UIColor.black.cgColor
        selectionRing.layer.shadowOffset = CGSize(width: 0, height: 3)
        selectionRing.layer.shadowRadius = 5
        selectionRing.layer.shadowOpacity = 0
        selectionRing.transform = CGAffineTransform(scaleX: 0.65, y: 0.65)
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
        let selected = isSelected
        isVisuallyHighlighted = selected
        let changes = {
            self.selectionRing.alpha = selected ? 1 : 0
            self.selectionRing.transform = selected ? .identity : CGAffineTransform(scaleX: 0.65, y: 0.65)
            self.selectionRing.layer.shadowOpacity = selected ? 0.35 : 0
            self.iconImageView.tintColor = selected ? .white : .label
            self.iconImageView.alpha = selected ? 1 : (self.isStale ? 0.4 : 1)
            self.callsignLabel.textColor = selected ? .white : .label
            self.callsignLabel.backgroundColor = selected
                ? .systemBlue
                : UIColor.systemBackground.withAlphaComponent(0.72)
        }
        displayPriority = selected ? .required : .defaultHigh
        zPriority = selected ? .defaultSelected : .defaultUnselected
        accessibilityValue = [isStale ? "Stale" : nil, selected ? "Selected aircraft" : "Aircraft"]
            .compactMap { $0 }
            .joined(separator: ", ")
        if animated {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0.4,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: changes
            )
        } else {
            changes()
        }
    }

    private func updateIcon(for aircraft: Aircraft) {
        let configuration = UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        iconImageView.image = UIImage(systemName: aircraft.aircraftType.systemImage, withConfiguration: configuration)
    }
}
