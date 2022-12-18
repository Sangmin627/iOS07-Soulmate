//
//  RegisterViewModel.swift
//  Soulmate
//
//  Created by Sangmin Lee on 2022/11/21.
//

import Foundation
import Combine
import FirebaseAuth

struct RegisterViewModelAction {
    var quitRegister: (() -> Void)?
    var finishRegister: (() -> Void)?
}

class RegisterViewModel: ViewModelable {
    
    // MARK: Interface defined AssociatedType
    
    typealias Action = RegisterViewModelAction
    
    struct Input {
        var didChangedPageIndex: AnyPublisher<Int, Never>
        var didChangedGenderType: AnyPublisher<GenderType?, Never>
        var didChangedNickNameValue: AnyPublisher<String?, Never>
        var didChangedHeightValue: AnyPublisher<Int, Never>
        var didChangedBirthValue: AnyPublisher<Date, Never>
        var didChangedMbtiValue: AnyPublisher<Mbti?, Never>
        var didChangedSmokingType: AnyPublisher<SmokingType?, Never>
        var didChangedDrinkingType: AnyPublisher<DrinkingType?, Never>
        var didChangedIntroductionValue: AnyPublisher<String?, Never>
        var didChangedImageListValue: AnyPublisher<[Data?], Never>
        var didTappedNextButton: AnyPublisher<Void, Never>
    }
    
    struct Output {
        var isNextButtonEnabled: AnyPublisher<Bool, Never>
        var isProfilImageSetted: AnyPublisher<Data?, Never>
        var isAllInfoUploaded: AnyPublisher<Void, Never>
    }
    
    // MARK: UseCase
    
    var uploadDetailInfoUseCase: UploadMyDetailInfoUseCase
    var uploadPictureUseCase: UploadPictureUseCase
    var uploadPreviewUseCase: UploadMyPreviewUseCase
    var heartUpdateUseCase: HeartUpdateUseCase
    
    // MARK: Properties
    
    var actions: Action?
    var bag = Set<AnyCancellable>()
    
    var currentPage: Int?
    var chatImageData: Data?

    var didAllInfoUploaded = PassthroughSubject<Void, Never>()
    @Published var genderType: GenderType?
    @Published var nickName: String?
    @Published var height: Int = Int()
    @Published var birth: Date = Date()
    @Published var mbti: Mbti?
    @Published var smokingType: SmokingType?
    @Published var drinkingType: DrinkingType?
    @Published var introduction: String?
    @Published var photoData: [Data?] = [nil, nil, nil, nil, nil]
    
    // MARK: Configuration
    
    init(
        uploadDetailInfoUseCase: UploadMyDetailInfoUseCase,
        uploadPictureUseCase: UploadPictureUseCase,
        uploadPreviewUseCase: UploadMyPreviewUseCase,
        heartUpdateUseCase: HeartUpdateUseCase
    ) {
        self.uploadDetailInfoUseCase = uploadDetailInfoUseCase
        self.uploadPictureUseCase = uploadPictureUseCase
        self.uploadPreviewUseCase = uploadPreviewUseCase
        self.heartUpdateUseCase = heartUpdateUseCase
    }
    
    func setPrevRegisterInfo(registerUserInfo: UserDetailInfo?) {
        guard let registerUserInfo = registerUserInfo else { return }
        
        self.genderType = registerUserInfo.gender
        self.nickName = registerUserInfo.nickName
        self.height = registerUserInfo.height == nil ? Int() : registerUserInfo.height!
        self.birth = registerUserInfo.birthDay == nil ? Date() : registerUserInfo.birthDay!
        self.mbti = registerUserInfo.mbti
        self.smokingType = registerUserInfo.smokingType
        self.drinkingType = registerUserInfo.drinkingType
        self.introduction = registerUserInfo.aboutMe
    }
    
    func setActions(actions: Action) {
        self.actions = actions
    }
    
    // MARK: Data Bind
    
    func transform(input: Input) -> Output {
        
        let valueChangedInCurrentPage = PassthroughSubject<Bool, Never>()
        let valueInChangedPage = input.didChangedPageIndex
            .map { [weak self] index in
                self?.currentPage = index
                guard let self else { return true }
                switch index {
                case 0: return self.genderType != nil
                case 1: return self.nickName != nil
                case 4: return self.mbti != nil
                case 5: return self.smokingType != nil
                case 6: return self.drinkingType != nil
                case 7: return self.introduction != nil
                case 8: return self.photoData.allSatisfy { $0 != nil }
                default: return true
                }
            }
            .eraseToAnyPublisher()
        
        input.didChangedGenderType
            .sink { value in
                self.genderType = value
                valueChangedInCurrentPage.send(value != nil)
            }
            .store(in: &bag)

        input.didChangedNickNameValue
            .sink { value in
                self.nickName = value
                valueChangedInCurrentPage.send(value != nil && !value!.isEmpty)
            }
            .store(in: &bag)
        
        input.didChangedHeightValue
            .assign(to: \.height, on: self)
            .store(in: &bag)
        
        input.didChangedBirthValue
            .assign(to: \.birth, on: self)
            .store(in: &bag)
        
        input.didChangedMbtiValue
            .sink { value in
                self.mbti = value
                valueChangedInCurrentPage.send(value != nil)
            }
            .store(in: &bag)
        
        input.didChangedSmokingType
            .sink { value in
                self.smokingType = value
                valueChangedInCurrentPage.send(value != nil)
            }
            .store(in: &bag)
        
        input.didChangedDrinkingType
            .sink { value in
                self.drinkingType = value
                valueChangedInCurrentPage.send(value != nil)
            }
            .store(in: &bag)
        
        input.didChangedIntroductionValue
            .sink { value in
                self.introduction = value
                valueChangedInCurrentPage.send(value != nil)
            }
            .store(in: &bag)
        
        input.didChangedImageListValue
            .sink { value in
                self.photoData = value
                valueChangedInCurrentPage.send(value.allSatisfy { $0 != nil })
            }
            .store(in: &bag)
        
        input.didTappedNextButton
            .sink { [weak self] _ in
                guard let index = self?.currentPage else { return }
                switch index {
                case 0...8:
                    self?.register()
                case 9:
                    self?.finalRegister()
                default:
                    return
                }
            }
            .store(in: &bag)
        
        let isNextButtonEnabled = valueChangedInCurrentPage.merge(with: valueInChangedPage).eraseToAnyPublisher()

        
        return Output(
            isNextButtonEnabled: isNextButtonEnabled,
            isProfilImageSetted: $photoData.map { $0[0] }.eraseToAnyPublisher(),
            isAllInfoUploaded: didAllInfoUploaded.eraseToAnyPublisher()
        )
    }
    
    // MARK: Logic
    
    func quit() {
        actions?.quitRegister?()
    }
    
    func finalRegister() {
        Task { [weak self] in
            let start = CFAbsoluteTimeGetCurrent()
            
            guard let chatImageData = self?.chatImageData else { return }
            
            let chatImageKey = try await uploadPictureUseCase.uploadChatImageData(photoData: chatImageData)
            let keys = try await uploadPictureUseCase.uploadPhotoData(photoData: photoData)
            
            let userPreview = UserPreview(
                gender: self?.genderType,
                name: self?.nickName,
                birth: self?.birth,
                imageKey: keys.first,
                chatImageKey: chatImageKey
            )
            try await uploadPreviewUseCase.registerPreview(userPreview: userPreview)

            let userInfo = UserDetailInfo(
                gender: self?.genderType,
                nickName: self?.nickName,
                birthDay: self?.birth,
                height: self?.height,
                mbti: self?.mbti,
                smokingType: self?.smokingType,
                drinkingType: self?.drinkingType,
                aboutMe: self?.introduction,
                imageList: keys
            )
            try await uploadDetailInfoUseCase.uploadDetailInfo(registerUserInfo: userInfo)
            try await heartUpdateUseCase.registerHeart(heart: 30)
            
            let diff = CFAbsoluteTimeGetCurrent() - start
            try await Task.sleep(nanoseconds: UInt64((5 > diff ? 5 - diff : 0) * 1_000_000_000))
            
            self?.didAllInfoUploaded.send(())
        }
    }
    
    func register() {
        Task { [weak self] in
                        
            let userInfo = UserDetailInfo(
                gender: self?.genderType,
                nickName: self?.nickName,
                birthDay: self?.birth,
                height: self?.height,
                mbti: self?.mbti,
                smokingType: self?.smokingType,
                drinkingType: self?.drinkingType,
                aboutMe: self?.introduction
            )
            
            try await uploadDetailInfoUseCase.uploadDetailInfo(registerUserInfo: userInfo)
        }
    }
}
