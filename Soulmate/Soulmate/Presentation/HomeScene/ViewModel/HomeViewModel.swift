//
//  HomeViewModel.swift
//  Soulmate
//
//  Created by termblur on 2022/11/22.
//

import Foundation
import Combine

struct HomeViewModelAction {
    var showDetailVC: ((DetailPreviewViewModel) -> Void)?
    var showHeartShopFlow: (() -> Void)?
}

final class HomeViewModel: ViewModelable {
    
    // MARK: Interface defined AssociatedType

    typealias Action = HomeViewModelAction

    struct Input {
        var viewDidLoad: AnyPublisher<Void, Never>
        var didTappedRefreshButton: AnyPublisher<Void, Never>
        var didSelectedMateCollectionCell: AnyPublisher<Int, Never>
        var didTappedHeartButton: AnyPublisher<Void, Never>
        var tokenUpdateEvent: AnyPublisher<String, Never>
    }
    
    struct Output {
        var didRefreshedPreviewList: AnyPublisher<[HomePreviewViewModel]?, Never>
        var didUpdatedHeartInfo: AnyPublisher<UserHeartInfo?, Never>
        var didStartRefreshing: AnyPublisher<Void, Never>
        var lessHeart: AnyPublisher<Void, Never>
    }
    
    // MARK: UseCase
    let mateRecommendationUseCase: MateRecommendationUseCase
    let downloadPictureUseCase: DownLoadPictureUseCase
    let uploadLocationUseCase: UpLoadLocationUseCase
    let getLocalLocationPublisherUseCase: GetLocalLocationPublisherUseCase
    let getDistanceUseCase: GetDistanceUseCase
    let listenHeartUpdateUseCase: ListenHeartUpdateUseCase
    let updateFCMTokenUseCase: UpdateFCMTokenUseCase
    let heartUpdateUseCase: HeartUpdateUseCase

    // MARK: Properties
    var actions: Action?
    var cancellables = Set<AnyCancellable>()
    
    @Published var matePreviewViewModelList: [HomePreviewViewModel]?
    @Published var currentLocation: Location? // 애는 첫 1회만 업댓시 바인딩해서 리프레시, 그다음부턴 프로퍼티처럼 사용됨
    @Published var distance: Double
    @Published var heartInfo: UserHeartInfo?
    
    var refreshStartEventPublisher = PassthroughSubject<Void, Never>()
    var lessHeartEventPublisher = PassthroughSubject<Void, Never>()

    // MARK: Configuration

    init(
        mateRecommendationUseCase: MateRecommendationUseCase,
        downloadPictureUseCase: DownLoadPictureUseCase,
        uploadLocationUseCase: UpLoadLocationUseCase,
        getLocalLocationPublisherUseCase: GetLocalLocationPublisherUseCase,
        getDistanceUseCase: GetDistanceUseCase,
        listenHeartUpdateUseCase: ListenHeartUpdateUseCase,
        updateFCMTokenUseCase: UpdateFCMTokenUseCase,
        heartUpdateUseCase: HeartUpdateUseCase
    ) {
        self.mateRecommendationUseCase = mateRecommendationUseCase
        self.downloadPictureUseCase = downloadPictureUseCase
        self.uploadLocationUseCase = uploadLocationUseCase
        self.getLocalLocationPublisherUseCase = getLocalLocationPublisherUseCase
        self.getDistanceUseCase = getDistanceUseCase
        self.listenHeartUpdateUseCase = listenHeartUpdateUseCase
        self.updateFCMTokenUseCase = updateFCMTokenUseCase
        self.heartUpdateUseCase = heartUpdateUseCase
        
        self.distance = getDistanceUseCase.getDistance()
    }

    func setActions(actions: Action) {
        self.actions = actions
    }

    // MARK: Data Bind
    func bind() {
        getDistanceUseCase.getDistancePublisher()
            .assign(to: \.distance, on: self)
            .store(in: &cancellables)
        
        $currentLocation
            .compactMap { $0 }
            .first()
            .sink { value in
                self.refresh(isInit: true)
            }
            .store(in: &cancellables)
        
        $distance
            .dropFirst()
            .sink { [weak self] value in
                self?.refresh(isInit: true)
            }
            .store(in: &cancellables)
        
        listenHeartUpdateUseCase.heartInfoSubject
            .sink { [weak self] value in
                self?.heartInfo = value
            }
            .store(in: &cancellables)
        
        getLocalLocationPublisherUseCase
            .execute()
            .sink { [weak self] location in
                print(location)
                self?.updateLocation(location: location)
            }
            .store(in: &cancellables)
    }
    
    func transform(input: Input) -> Output {

        input.viewDidLoad
            .sink { [weak self] in
                self?.listenHeartUpdateUseCase.listenHeartUpdate()
                self?.bind()
            }
            .store(in: &cancellables)
        
        input.tokenUpdateEvent
            .sink { [weak self] token in
                Task { [weak self] in
                    try await self?.updateFCMTokenUseCase.execute(token: token)
                }
            }
            .store(in: &cancellables)
        
        input.didTappedRefreshButton
            .sink { [weak self] _ in
                self?.refresh(isInit: false)
            }
            .store(in: &cancellables)
        
        input.didSelectedMateCollectionCell
            .receive(on: DispatchQueue.main)
            .sink { [weak self] index in
                self?.mateSelected(index: index)
            }
            .store(in: &cancellables)

        input.didTappedHeartButton
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.actions?.showHeartShopFlow?()
            }
            .store(in: &cancellables)
        
        return Output(
            didRefreshedPreviewList: $matePreviewViewModelList.eraseToAnyPublisher(),
            didUpdatedHeartInfo: $heartInfo.eraseToAnyPublisher(),
            didStartRefreshing: refreshStartEventPublisher.eraseToAnyPublisher(),
            lessHeart: lessHeartEventPublisher.eraseToAnyPublisher()
        )
    }
    
    // MARK: Logic
    
    func refresh(isInit: Bool) {
        
        Task { [weak self] in
            let start = CFAbsoluteTimeGetCurrent()
            do {
                if !isInit {
                    try await heartUpdateUseCase.updateHeart(heart: -10)
                }
            }
            catch HeartShopError.lessHeart {
                self?.lessHeartEventPublisher.send(())
                return
            }
            refreshStartEventPublisher.send(())
            guard let currentLocation = self?.currentLocation  else { return }
            let previewList = try await mateRecommendationUseCase
                .fetchDistanceFilteredRecommendedMate(from: currentLocation, distance: distance)

            var homePreviewViewModelList: [HomePreviewViewModel] = []
            
            for preview in previewList {
                guard let uid = preview.uid,
                      let imageKey = preview.imageKey,
                      let name = preview.name,
                      let birth = preview.birth,
                      let location = preview.location else { continue }
                homePreviewViewModelList.append(
                    HomePreviewViewModel(
                        uid: uid,
                        imageKey: imageKey,
                        name: name,
                        age: String(birth.toAge()),
                        address: try await location.address(),
                        distance: String(format: "%.2fkm", Location.distance(from: currentLocation, to: location))
                    )
                )
            }
            
            let diff = CFAbsoluteTimeGetCurrent() - start
            try await Task.sleep(nanoseconds: UInt64((1 > diff ? 1 - diff : 0) * 1_000_000_000))
            
            self?.matePreviewViewModelList = homePreviewViewModelList
        }
    }
    
    func fetchImage(key: String) async throws -> Data? {
        return try await downloadPictureUseCase.downloadPhotoData(keyList: [key]).first
    }
    
    func mateSelected(index: Int) {
        guard let selectedMatePreviewViewModel = matePreviewViewModelList?[index] else { return }
        let detailPreviewViewModel = DetailPreviewViewModel(
            uid: selectedMatePreviewViewModel.uid,
            name: selectedMatePreviewViewModel.name,
            age: selectedMatePreviewViewModel.age,
            address: selectedMatePreviewViewModel.address,
            distance: selectedMatePreviewViewModel.distance
        )
        actions?.showDetailVC?(detailPreviewViewModel)
    }
    
    func updateLocation(location: Location) {
        Task {
            self.currentLocation = location
            try await uploadLocationUseCase.updateLocation(location: location)
        }
    }

}
