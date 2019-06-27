import UIKit
import Photos
import FDTake
import IIDelayedAction
import JGProgressHUD

let IS_IPAD = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiom.pad
let IS_IPHONE = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiom.phone
let SCREEN_WIDTH = UIScreen.main.bounds.size.width
let SCREEN_HEIGHT = UIScreen.main.bounds.size.height
let IS_LARGE_SCREEN = IS_IPHONE && max(SCREEN_WIDTH, SCREEN_HEIGHT) >= 736.0

final class ViewController: UIViewController, UIScrollViewDelegate {
	var sourceImage: UIImage?
	var delayedAction: IIDelayedAction?
	var blurAmount: Float = 0
	let stockImages = Bundle.main.urls(forResourcesWithExtension: "jpg", subdirectory: "Bundled Photos")!
	lazy var randomImageIterator: AnyIterator<URL> = self.stockImages.uniqueRandomElement()
	var isFilterAdded:Bool = true
	lazy var imageView = with(UIImageView()) {
		$0.image = UIImage(color: .black, size: view.frame.size)
		$0.contentMode = .scaleAspectFill
		$0.clipsToBounds = true
		$0.frame = view.bounds
		let doubleTap = UITapGestureRecognizer(target: self, action: #selector(showFilter))
		doubleTap.numberOfTouchesRequired = 1
		doubleTap.numberOfTapsRequired = 2
		$0.addGestureRecognizer(doubleTap)

	}
	lazy var scrollView = with(UIScrollView()) {
		
		$0.delegate = self
		$0.frame = view.frame
		$0.alwaysBounceVertical = false
		$0.alwaysBounceHorizontal = false
		$0.showsVerticalScrollIndicator = true
		$0.flashScrollIndicators()
		$0.minimumZoomScale = 1.0
		$0.maximumZoomScale = 10.0
	}
	lazy var filtersScrollView = with(UIScrollView()) {
		$0.delegate = self
		$0.frame = view.frame
		$0.backgroundColor = .gray
		$0.alwaysBounceVertical = false
		$0.alwaysBounceHorizontal = false
		$0.showsHorizontalScrollIndicator = true
		$0.flashScrollIndicators()
	}
	lazy var slider = with(UISlider()) {
		let SLIDER_MARGIN: CGFloat = 120
		$0.frame = CGRect(x: 0, y: 0, width: view.frame.size.width - SLIDER_MARGIN, height: view.frame.size.height)
		$0.minimumValue = 0
		$0.maximumValue = 100
		$0.value = blurAmount
		$0.isContinuous = true
		$0.setThumbImage(UIImage(named: "SliderThumb")!, for: .normal)
		$0.autoresizingMask = [
			.flexibleWidth,
			.flexibleTopMargin,
			.flexibleBottomMargin,
			.flexibleLeftMargin,
			.flexibleRightMargin
		]
		$0.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
	}

	override var canBecomeFirstResponder: Bool {
		return true
	}

	override var prefersStatusBarHidden: Bool {
		return true
	}

	override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
		if motion == .motionShake {
			randomImage()
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		// This is to ensure that it always ends up with the current blur amount when the slider stops
		// since we're using `DispatchQueue.global().async` the order of events aren't serial
		delayedAction = IIDelayedAction({}, withDelay: 0.2)
		delayedAction?.onMainThread = false

		view.addSubview(scrollView)
		scrollView.addSubview(imageView)

		let tapGesture = UILongPressGestureRecognizer(target: self, action: #selector(tapGesture(gesture:)))
		imageView.addGestureRecognizer(tapGesture)
		imageView.isUserInteractionEnabled = true

		let TOOLBAR_HEIGHT: CGFloat = 80 + window.safeAreaInsets.bottom
		let toolbar = UIToolbar(frame: CGRect(x: 0, y: view.frame.size.height - TOOLBAR_HEIGHT, width: view.frame.size.width, height: TOOLBAR_HEIGHT))
		toolbar.autoresizingMask = .flexibleWidth
		toolbar.alpha = 0.6
		toolbar.tintColor = #colorLiteral(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)

		// Remove background
		toolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
		toolbar.setShadowImage(UIImage(), forToolbarPosition: .any)

		// Gradient background
		let GRADIENT_PADDING: CGFloat = 40
		let gradient = CAGradientLayer()
		gradient.frame = CGRect(x: 0, y: -GRADIENT_PADDING, width: toolbar.frame.size.width, height: toolbar.frame.size.height + GRADIENT_PADDING)
		gradient.colors = [
			UIColor.clear.cgColor,
			UIColor.black.withAlphaComponent(0.1).cgColor,
			UIColor.black.withAlphaComponent(0.3).cgColor,
			UIColor.black.withAlphaComponent(0.4).cgColor
		]
		toolbar.layer.addSublayer(gradient)

		toolbar.items = [
			UIBarButtonItem(image: UIImage(named: "PickButton")!, target: self, action: #selector(pickImage), width: 20),
			.flexibleSpace,
			UIBarButtonItem(customView: slider),
			.flexibleSpace,
			UIBarButtonItem(image: UIImage(named: "SaveButton")!, target: self, action: #selector(saveImage), width: 20)
		]
		view.addSubview(toolbar)

		// Important that this is here at the end for the fading to work
		randomImage()
		
		let SCROLL_HEIGHT: CGFloat = 80 + window.safeAreaInsets.bottom
		filtersScrollView.frame = CGRect(x: 0, y: view.frame.size.height - SCROLL_HEIGHT, width: view.frame.size.width, height: SCROLL_HEIGHT)
		view.addSubview(filtersScrollView)

		self.addFilter()
		
	}
	func addFilter () {
		var CIFilterNames = [
			"CIPhotoEffectChrome",
			"CIPhotoEffectFade",
			"CIPhotoEffectInstant",
			"CIPhotoEffectNoir",
			"CIPhotoEffectProcess",
			"CIPhotoEffectTonal",
			"CIPhotoEffectTransfer",
			"CISepiaTone"
		]
		
		// Variables for setting the Font Buttons
		var xCoord: CGFloat = 5
		let yCoord: CGFloat = 5
		let buttonWidth: CGFloat = 70
		let buttonHeight: CGFloat = 70
		let gapBetweenButtons: CGFloat = 5
		// Items Counter
		var itemCount = 0
		
		// Loop for creating buttons ------------------------------------------------------------
		for index in 0..<CIFilterNames.count {
			itemCount = index
			
			// Button properties
			let filterButton = UIButton(type: .custom)
			filterButton.frame = CGRect(x: xCoord, y: yCoord, width: buttonWidth, height: buttonHeight)
			filterButton.tag = itemCount
			filterButton.addTarget(self, action: #selector(filterButtonTapped(sender:)), for: .touchUpInside)
			filterButton.layer.cornerRadius = 6
			filterButton.clipsToBounds = true
			
			//			// Create filters for each button
			let ciContext = CIContext(options: nil)
			let coreImage = CIImage(image: imageView.image!)
			let filter = CIFilter(name: "\(CIFilterNames[index])" )
			filter!.setDefaults()
			filter!.setValue(coreImage, forKey: kCIInputImageKey)
			let filteredImageData = filter!.value(forKey: kCIOutputImageKey) as! CIImage
			let filteredImageRef = ciContext.createCGImage(filteredImageData, from: filteredImageData.extent)
			let imageForButton = UIImage(cgImage: filteredImageRef!);
			
			// Assign filtered image to the button
			filterButton.setBackgroundImage(imageForButton, for: .normal)
			
			// Add Buttons in the Scroll View
			xCoord +=  buttonWidth + gapBetweenButtons
			filtersScrollView.addSubview(filterButton)
		}
		
		filtersScrollView.contentSize = CGSize(width: buttonWidth * CGFloat(itemCount+2), height: yCoord)

	}
	@objc
	func showFilter () {
		
		if isFilterAdded {
			filtersScrollView.isHidden = true
			isFilterAdded = false
			return
		}
		isFilterAdded = true
		filtersScrollView.isHidden = false
	}
	
	// FILTER BUTTON ACTION
	@objc
	func filterButtonTapped(sender: UIButton) {
		let button = sender as UIButton
		
		imageView.image = button.backgroundImage(for: UIControl.State.normal)
		sourceImage = imageView.toImage()

	}
	
	@objc
	func tapGesture(gesture: UIGestureRecognizer) {
		if let image = imageView.image {
			let vc = UIActivityViewController(activityItems: [image], applicationActivities: [])
			present(vc, animated: true)
		}
	}
	@objc
	func pickImage() {
		let fdTake = FDTakeController()
		fdTake.allowsVideo = false
		fdTake.didGetPhoto = { photo, _ in
			self.changeImage(photo)
		}
		fdTake.present()
	}

	func blurImage(_ blurAmount: Float) -> UIImage {
		return UIImageEffects.imageByApplyingBlur(
			to: sourceImage,
			withRadius: CGFloat(blurAmount * (IS_LARGE_SCREEN ? 0.8 : 1.2)),
			tintColor: UIColor(white: 1, alpha: CGFloat(max(0, min(0.25, blurAmount * 0.004)))),
			saturationDeltaFactor: CGFloat(max(1, min(2.8, blurAmount * (IS_IPAD ? 0.035 : 0.045)))),
			maskImage: nil
		)
	}

	@objc
	func updateImage() {
		DispatchQueue.global(qos: .userInteractive).async {
			let tmp = self.blurImage(self.blurAmount)
			DispatchQueue.main.async {
				self.imageView.image = tmp
			}
		}
	}

	func viewForZooming(in scrollView: UIScrollView) -> UIView? {
		return imageView
	}
	
	func updateImageDebounced() {
		performSelector(inBackground: #selector(updateImage), with: IS_IPAD ? 0.1 : 0.06)
	}

	@objc
	func sliderChanged(_ sender: UISlider) {
		blurAmount = sender.value
		updateImageDebounced()
		delayedAction?.action {
			self.updateImage()
		}
	}

	@objc
	func saveImage(_ button: UIBarButtonItem) {
		button.isEnabled = false

		PHPhotoLibrary.save(image: imageView.image!, toAlbum: "Blear") { result in
			button.isEnabled = true

			let HUD = JGProgressHUD(style: .dark)
			HUD.indicatorView = JGProgressHUDSuccessIndicatorView()
			HUD.animation = JGProgressHUDFadeZoomAnimation()
			HUD.vibrancyEnabled = true
			HUD.contentInsets = UIEdgeInsets(all: 30)

			if case .failure(let error) = result {
				HUD.indicatorView = JGProgressHUDErrorIndicatorView()
				HUD.textLabel.text = error.localizedDescription
				HUD.show(in: self.view)
				HUD.dismiss(afterDelay: 3)
				return
			}

			//HUD.indicatorView = JGProgressHUDImageIndicatorView(image: #imageLiteral(resourceName: "HudSaved"))
			HUD.show(in: self.view)
			HUD.dismiss(afterDelay: 0.8)

			// Only on first save
			if UserDefaults.standard.isFirstLaunch {
				delay(seconds: 1) {
					let alert = UIAlertController(
						title: "Changing Wallpaper",
						message: "In the Photos app go to the wallpaper you just saved, tap the action button on the bottom left and choose 'Use as Wallpaper'.",
						preferredStyle: .alert
					)
					alert.addAction(UIAlertAction(title: "OK", style: .default))
					self.present(alert, animated: true)
				}
			}
		}
	}

	/// TODO: Improve this method
	func changeImage(_ image: UIImage) {
		let tmp = NSKeyedUnarchiver.unarchiveObject(with: NSKeyedArchiver.archivedData(withRootObject: imageView)) as! UIImageView
		view.insertSubview(tmp, aboveSubview: imageView)
		imageView.image = image
		sourceImage = imageView.toImage()
		updateImageDebounced()

		// The delay here is important so it has time to blur the image before we start fading
		UIView.animate(
			withDuration: 0.6,
			delay: 0.3,
			options: .curveEaseInOut,
			animations: {
				tmp.alpha = 0
			}, completion: { _ in
				tmp.removeFromSuperview()
			}
		)
	}

	func randomImage() {
		changeImage(UIImage(contentsOf: randomImageIterator.next()!)!)
	}
}
